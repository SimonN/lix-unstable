module net.client;

/* Interactive mode runs an instance of this during network games.
 * This is the high-level message API that the game and lobby call when
 * they want to send stuff over the network.
 * This receives data from a NetServer and caches it for the gameplay.
 */

import std.algorithm;
import std.array;
import std.string;
import std.exception;
import derelict.enet.enet;

import net.enetglob;
import net.header;
import net.iclient;
import net.packetid;
import net.permu;
import net.plnr;
import net.profile;
import net.repdata;
import net.structs;
import net.style;
import net.versioning;

struct NetClientCfg {
    string hostname;
    int port;
    Version clientVersion;
    string ourPlayerName;
    Style ourStyle;
}

class NetClient : INetClient {
private:
    ENetHost* _ourClient;
    ENetPeer* _serverPeer;
    NetClientObserver[] _observers;

    NetClientCfg _cfg;
    PlNr _ourPlNr;
    Room _ourRoom = Room(0);
    Profile2022[PlNr] _profilesInOurRoom;

public:
    /* Immediately tries to connect to hostname:port.
     * Hostname can be a domain, e.g., "example.com" or "localhost",
     * or a dot-separated decimal IP address, e.g. "127.0.0.1"
     */
    this(NetClientCfg cfg)
    {
        initializeEnet();
        _cfg = cfg;
        _ourClient = enet_host_create(null, // create a client == no listener
            1, // allow up to 1 outgoing connection
            2, // allow up to 2 channels to be used, 0 and 1
            0, // unlimited downstream from the server
            0); // unlimited upstream to the server
        enforce(_ourClient, "error creating enet client host");
        ENetAddress address;
        enet_address_set_host(&address, _cfg.hostname.toStringz);
        address.port = _cfg.port & 0xFFFF;
        _serverPeer = enet_host_connect(_ourClient, &address, 2, 0);
        enforce(_serverPeer, "no available peers for an enet connection");

        // We display a disconnection to our user when the server hasn't
        // replied after about 5 to 10 seconds.
        enet_peer_timeout(_serverPeer, 0, 5_000, 5_000);
    }

    void disconnectAndDispose()
    {
        if (connected || connecting) {
            enet_peer_disconnect_now(_serverPeer, 0);
            enet_host_flush(_ourClient);
            // We won't wait for the disconnection return packet.
        }
        if (_ourClient) {
            enet_host_destroy(_ourClient);
            _ourClient = null;
        }
        _serverPeer = null;
        _profilesInOurRoom.clear();
        _observers = [];
        deinitializeEnet();
    }

    void calc() { implCalc(); }

    void register(NetClientObserver obs)
    {
        assert (! _observers.canFind(obs), "Don't add same observer twice");
        _observers ~= obs;
    }

    void unregister(NetClientObserver obs)
    {
        assert (_observers.canFind(obs), "Can't remove unknown observer");
        _observers = _observers[].remove!(entry => entry is obs);
    }

    void sendChatMessage(string aText)
    {
        assert (_ourClient);
        assert (_serverPeer);
        ChatPacket chat;
        chat.header.packetID = PacketCtoS.chatMessage;
        chat.text = aText;
        chat.enetSendTo(_serverPeer);
    }

    @property bool connected() const
    {
        return _ourClient && _serverPeer && _ourPlNr in _profilesInOurRoom;
    }

    @property bool connecting() const
    {
        return _ourClient && _serverPeer && ! (_ourPlNr in _profilesInOurRoom);
    }

    @property string enetLinkedVersion() const
    {
        return net.enetglob.enetLinkedVersion();
    }

    @property PlNr ourPlNr() const pure
    {
        assert (connected, "call this function only when you're connected");
        return _ourPlNr;
    }

    @property Room ourRoom() const pure
    {
        assert (connected, "call this function only when you're connected");
        return _ourRoom;
    }

    @property const(Profile2022) ourProfile() const
    {
        assert (connected, "call this function only when you're connected");
        return _profilesInOurRoom[_ourPlNr];
    }

    @property const(Profile2022[PlNr]) profilesInOurRoom() const
    {
        return _profilesInOurRoom;
    }

    @property bool mayWeDeclareReady() const
    {
        if (! connected
            || _ourRoom == Room(0)
            || _profilesInOurRoom.length < 2
            || _profilesInOurRoom.byValue.all!(pro
                => pro.feeling == Profile2022.Feeling.observing)
        ) {
            return false;
        }
        final switch (ourProfile.feeling) {
            case Profile2022.Feeling.thinking: return true;
            case Profile2022.Feeling.ready: return true;
            case Profile2022.Feeling.observing: return false;
        }
    }

    // Call this when the GUI has chosen a new Lix style.
    // The GUI may update ahead of time, but what the server knows, decides.
    @property void ourStyle(Style sty)
    {
        _cfg.ourStyle = sty;
        sendOurUpdatedProfile((ref Profile2016 p) {
            p.style = sty;
            p.feeling = Profile2016.Feeling.thinking; // = not observing
        });
    }

    // Feeling is readiness, and whether we want to observe.
    @property void ourFeeling(Profile2022.Feeling feel)
    {
        sendOurUpdatedProfile((ref Profile2016 p) { p.feeling = feel; });
    }

    void gotoExistingRoom(Room newRoom)
    {
        if (! connected)
            return;
        RoomChangePacket wish;
        wish.header.packetID = PacketCtoS.toExistingRoom;
        wish.room = newRoom;
        wish.enetSendTo(_serverPeer);
    }

    void createRoom()
    {
        if (! connected)
            return;
        PacketHeader2016 wish;
        wish.packetID = PacketCtoS.createRoom;
        wish.enetSendTo(_serverPeer);
    }

    void selectLevel(const(void[]) buffer)
    {
        if (! connected)
            return;
        struct LevelPacket {
            ENetPacket* createPacket() const nothrow @nogc {
                ENetPacket* ret = .createPacket(buffer.length + 2);
                ret.data[0] = PacketCtoS.levelFile;
                ret.data[2 .. ret.dataLength]
                    = (cast (const(ubyte[])) buffer)[0 .. $];
                return ret;
            }
        }
        LevelPacket().enetSendTo(_serverPeer);
    }

    void sendPly(in Ply data)
    {
        if (! connected)
            return;
        data.enetSendTo(_serverPeer, PacketCtoS.myPly);
    }

private:
    void implCalc()
    {
        if (! _ourClient || ! _serverPeer) // stricter than if (! connected)
            return;
        ENetEvent event;
        // We test _ourClient every loop iteration, because the Lobby can
        // tell us to disconnect in a callback, or we can destroy ourselves
        // on disconnect.
        while (_ourClient && enet_host_service(_ourClient, &event, 0) > 0)
            final switch (event.type) {
            case ENET_EVENT_TYPE_NONE:
                assert (false, "enet_host_service should have returned 0");
            case ENET_EVENT_TYPE_CONNECT:
                sayHello();
                break;
            case ENET_EVENT_TYPE_RECEIVE:
                receivePacket(event.packet);
                enet_packet_destroy(event.packet);
                break;
            case ENET_EVENT_TYPE_DISCONNECT:
                foreach (obs; _observers) {
                    if (connected) {
                        obs.onConnectionLost();
                    }
                    else {
                        obs.onCannotConnect();
                    }
                }
                disconnectAndDispose();
                break;
            }
        if (_ourClient)
            enet_host_flush(_ourClient);
    }

    string toDottedIpAddress(uint inNetworkByteOrder)
    {
        ubyte* ptr = cast (ubyte*) &inNetworkByteOrder;
        return "%d.%d.%d.%d".format(ptr[0], ptr[1], ptr[2], ptr[3]);
    }

    string playerName(PlNr plNr)
    {
        auto ptr = plNr in _profilesInOurRoom;
        return ptr ? ptr.name : "?";
    }

    void sayHello()
    {
        HelloPacket hello;
        hello.header.packetID = PacketCtoS.hello;
        hello.fromVersion = _cfg.clientVersion;
        hello.profile = generateOurProfile2016();
        assert (_serverPeer);
        hello.enetSendTo(_serverPeer);
    }

    Profile2016 generateOurProfile2016()
    {
        Profile2016 ret;
        ret.name = _cfg.ourPlayerName;
        ret.style = _cfg.ourStyle;
        return ret;
    }

    void sendOurUpdatedProfile(void delegate(ref Profile2016) howToChange)
    {
        if (! connected)
            return;
        // Never affect our profiles directly. Always send the desire
        // to change color over the network and wait for the return packet.
        ProfilePacket2016 newStyle;
        newStyle.header.packetID = PacketCtoS.myProfile;
        newStyle.profile = _profilesInOurRoom[_ourPlNr].to2016with(_ourRoom);
        howToChange(newStyle.profile);
        newStyle.enetSendTo(_serverPeer);
    }

    Profile2022* receiveProfilePacket(ENetPacket* got)
    {
        auto updated = ProfilePacket2016(got);
        auto ptr = updated.header.plNr in _profilesInOurRoom;
        if (ptr is null || ptr.wouldForceAllNotReadyOnReplace(
            updated.profile.to2022with(_cfg.clientVersion))
        ) {
            foreach (ref profile; _profilesInOurRoom)
                profile.setNotReady();
        }
        /*
         * Insert the received profile into our list.
         * Hack in the 2016 client: We assume that everybody else has our
         * version because the server doesn't tell us our version.
         * The server will tell 2022 clients the correct remote client version.
         */
        _ourRoom = updated.profile.room;
        _profilesInOurRoom[updated.header.plNr]
            = updated.profile.to2022with(_cfg.clientVersion);
        return updated.header.plNr in _profilesInOurRoom;
    }

    void receivePacket(ENetPacket* got)
    {
        if (got.dataLength < 1)
            return;
        else if (got.data[0] == PacketStoC.youGoodHeresPlNr) {
            auto answer = HelloAnswerPacket(got);
            _ourPlNr = answer.header.plNr;
            _profilesInOurRoom[_ourPlNr]
                = generateOurProfile2016().to2022with(_cfg.clientVersion);
            foreach (obs; _observers) {
                obs.onConnect();
            }
        }
        else if (got.data[0] == PacketStoC.youTooOld
            ||   got.data[0] == PacketStoC.youTooNew
        ) {
            auto answer = HelloAnswerPacket(got);
            foreach (obs; _observers) {
                obs.onVersionMisfit(answer.serverVersion);
            }
            disconnectAndDispose();
        }
        else if (got.data[0] == PacketStoC.peerJoinsYourRoom) {
            const(Profile2022*) changed = receiveProfilePacket(got);
            if (changed !is null) {
                foreach (obs; _observers) {
                    obs.onPeerJoinsRoom(*changed);
                }
            }
        }
        else if (got.data[0] == PacketStoC.peerLeftYourRoom) {
            auto gone = RoomChangePacket(got);
            auto ptr = gone.header.plNr in _profilesInOurRoom;
            auto name = ptr ? ptr.name : "?";
            _profilesInOurRoom.remove(gone.header.plNr);
            foreach (ref profile; _profilesInOurRoom)
                profile.setNotReady();
            foreach (obs; _observers) {
                obs.onPeerLeavesRoomTo(name, gone.room);
            }
        }
        else if (got.data[0] == PacketStoC.peersAlreadyInYourNewRoom) {
            auto list = ProfileListPacket2016(got);
            _profilesInOurRoom.clear();
            foreach (i, const(PlNr) plNr; list.indices) {
                _ourRoom = list.profiles[i].room;
                _profilesInOurRoom[plNr]
                    = list.profiles[i].to2022with(_cfg.clientVersion);
            }
            enforce(_ourPlNr in _profilesInOurRoom);
            foreach (obs; _observers) {
                obs.onWeChangeRoom(_ourRoom);
            }
        }
        else if (got.data[0] == PacketStoC.listOfExistingRooms) {
            auto list = RoomListPacket2016(got);
            if (_observers.length >= 1) {
                Profile2022[] converted = list.profiles.map!(p
                    => p.to2022with(_cfg.clientVersion)).array;
                foreach (obs; _observers) {
                    obs.onListOfExistingRooms(list.indices, converted);
                }
            }
        }
        else if (got.data[0] == PacketStoC.peerProfile) {
            const(Profile2022*) changed = receiveProfilePacket(got);
            if (changed !is null) {
                foreach (obs; _observers) {
                    obs.onPeerChangesProfile(*changed);
                }
            }
        }
        else if (got.data[0] == PacketStoC.peerChatMessage) {
            auto chat = ChatPacket(got);
            foreach (obs; _observers) {
                obs.onChatMessage(playerName(chat.header.plNr), chat.text);
            }
        }
        else if (got.data[0] == PacketStoC.peerLevelFile) {
            if (got.dataLength >= 2) {
                // We only display the level when we get it back from server.
                foreach (ref profile; _profilesInOurRoom)
                    profile.setNotReady();
                foreach (obs; _observers) {
                    obs.onLevelSelect(
                        playerName(PlNr(got.data[1])),
                        got.data[2 .. got.dataLength]);
                }
            }
        }
        else if (got.data[0] == PacketStoC.gameStartsWithPermu) {
            if (got.dataLength >= 3) {
                foreach (ref profile; _profilesInOurRoom)
                    profile.setNotReady();
                auto pa = StartGameWithPermuPacket(got);
                Permu permu = new Permu(pa.arr);
                foreach (obs; _observers) {
                    obs.onGameStart(permu);
                }
            }
        }
        else if (got.data[0] == PacketStoC.peerPly) {
            if (got.dataLength == Ply.len) {
                foreach (obs; _observers) {
                    obs.onPeerSendsPly(Ply(got));
                }
            }
        }
        else if (got.data[0] == PacketStoC.peerDisconnected) {
            auto discon = SomeoneDisconnectedPacket(got);
            auto ptr = discon.header.plNr in _profilesInOurRoom;
            auto name = ptr ? ptr.name : "?";
            _profilesInOurRoom.remove(discon.plNr);
            foreach (ref profile; _profilesInOurRoom)
                profile.setNotReady();
            foreach (obs; _observers) {
                obs.onPeerDisconnect(name);
            }
        }
        else if (got.data[0] == PacketStoC.millisecondsSinceGameStart) {
            assert (_serverPeer);
            foreach (obs; _observers) {
                obs.onMillisecondsSinceGameStart(
                    MillisecondsSinceGameStartPacket(got).milliseconds
                    + _serverPeer.roundTripTime);
            }
        }
    }
}
