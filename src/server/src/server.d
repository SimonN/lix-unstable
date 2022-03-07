module net.server.server;

/* The daemon runs an instance of this. This can take many connections
 * from other people's NetClients.
 *
 * The game runs a NetServer instance if you click (I want to be server)
 * in the lobby. Then, the game creates a NetClient too, connects to the
 * local NetServer, and treats that NetServer without knowing it's local.
 */

import std.algorithm;
import derelict.enet.enet;

import net.server.hotel;
import net.server.inbox;
import net.server.outbox;
import net.enetglob;
import net.packetid;
import net.permu;
import net.profile;
import net.structs;
import net.repdata;
import net.versioning;

class NetServer {
private:
    ENetHost* _host; // We own it.
    Hotel _hotel; // We create and own this.
    Inbox _inbox; // Forwards to our _hotel.
    Outbox _outbox; // Sends via our our _host.
    SendWithEnet _sendWithEnet; // We own it.

public:
    this(in int port)
    {
        initializeEnet();
        ENetAddress address;
        address.host = ENET_HOST_ANY;
        address.port = port & 0xFFFF;
        _host = enet_host_create(&address,
            127, // max connections. PlNr is ubyte, redesign PlNr if want more
            2, // allow up to 2 channels to be used, 0 and 1
            0, // assume any amount of incoming bandwidth
            0); // assume any amount of outgoing bandwidth
        assert (_host, "error creating enet server host");

        _sendWithEnet = new SendWithEnet(_host);
        _outbox = new Outbox2016(_sendWithEnet);
        _hotel = Hotel(_outbox);
        _inbox = new Inbox2016(&_hotel);
    }

    ~this()
    {
        if (_host) {
            enet_host_destroy(_host);
            _host = null;
        }
        _hotel.dispose();
        deinitializeEnet();
    }

    bool anyoneConnected() const { return ! _hotel.empty; }

    void calc()
    {
        assert (_host);
        ENetEvent event = void;
        while (enet_host_service(_host, &event, 0) > 0) {
            _sendWithEnet.computeSizeOfEnetPeer(event.peer);
            final switch (event.type) {
            case ENET_EVENT_TYPE_NONE:
                assert (false, "enet_host_service should have returned 0");
            case ENET_EVENT_TYPE_CONNECT:
                // Don't add the player to the hotel rooms yet.
                // We will do that when the peer sends its hello packet.
                break;
            case ENET_EVENT_TYPE_RECEIVE:
                receivePacket(peerToPlNr(event.peer), event.packet);
                enet_packet_destroy(event.packet);
                break;
            case ENET_EVENT_TYPE_DISCONNECT:
                // There are two types of disconnections:
                // We threw him out for old version by disconnect_later(),
                // then we don't have to do anything else now.
                // Or he disconnected by his own will. The difference is
                // whether he's in our player array. Remove from hotel and
                // let the hotel decide what to do.
                _hotel.removePlayerWhoHasDisconnected(peerToPlNr(event.peer));
                break;
            }
        }
        _hotel.calc();
        enet_host_flush(_host);
    }

// ############################################################################
private:
    void receivePacket(in PlNr from, ENetPacket* got)
    {
        assert (got);
        if (got.dataLength < 1)
            return;
        /* Convention:
         * When we make a struct from the packet data, this struct contains
         * a header, but we don't trust header.plNr. To see who sent this
         * packet, we always infer the plNr from peerToPlNr.
         */
        with (PacketCtoS) try switch (got.data[0]) {
            case hello: receiveHello(from, got); break;
            case toExistingRoom: _inbox.receiveRoomChange(from, got); break;
            case createRoom: _inbox.receiveCreateRoom(from, got); break;
            case myProfile: _inbox.receiveProfileChange(from, got); break;
            case chatMessage: _inbox.receiveChat(from, got); break;
            case levelFile: _inbox.receiveLevel(from, got); break;
            case myPly: _inbox.receivePly(from, got); break;
            default: break;
        }
        catch (Exception) {}
    }

    void receiveHello(in PlNr from, in ENetPacket* got)
    {
        immutable hello = HelloPacket(got);
        auto answer = HelloAnswerPacket();
        answer.header.plNr = from;
        answer.header.packetID = hello.fromVersion.compatibleWith(gameVersion)
                               ? PacketStoC.youGoodHeresPlNr
                               : hello.fromVersion < gameVersion
                               ? PacketStoC.youTooOld : PacketStoC.youTooNew;
        answer.serverVersion = gameVersion;
        _sendWithEnet.send(from, answer.createPacket);

        if (answer.header.packetID == PacketStoC.youGoodHeresPlNr) {
            _hotel.addNewPlayerToLobby(from, hello.profile);
        }
        else {
            _sendWithEnet.disconnectLater(from);
        }
    }
}

// ############################################################################
// ############################################################################
// ############################################################################

private PlNr peerToPlNr(in ENetPeer* peer) pure nothrow @safe @nogc
{
    return PlNr(peer.incomingPeerID & 0xFF);
}

private class SendWithEnet {
private:
    ENetHost* _host; // We don't own it. We merely know the server's host.

    /*
     * Hack to detect size of ENetPeer at runtime, independently from the
     * D bindings version.
     *
     * Why do I need it: For a given int x, I must be able to send to
     * _host.peers[x] in the C-style array _host.peers. Normally, one knows
     * where in memory that is by ENetPeer.sizeof. But this depends on the
     * C header or D bindings that we use at build time. People might have
     * all sorts of enet binaries installed, and we might not fetch the
     * correct D headers for their binaries.
     *
     * We use the header's answer sizeof(ENetPeer) until I get a packet
     * from a peer with peer.incomingPeerID == 1. Then I'll use that peer's
     * offset from _host.peers to overwrite sizeOfEnetPeer.
     */
    ptrdiff_t sizeOfEnetPeer = ENetPeer.sizeof;

    ENetPeer* plNrToPeer(in PlNr plNr) const pure nothrow @system @nogc
    {
        return cast(ENetPeer*)(cast(void*)_host.peers + plNr * sizeOfEnetPeer);
    }

public:
    this(ENetHost* viaWhichWeSend)
    {
        _host = viaWhichWeSend;
    }

    // Takes ownership of the packet.
    void send(in PlNr receiv, ENetPacket* what) @nogc
    {
        enetSendTo(what, plNrToPeer(receiv));
    }

    // Call this at least once before sending anything to that peer.
    void computeSizeOfEnetPeer(in ENetPeer* peerInArray) nothrow @system @nogc
    {
        if (peerInArray.incomingPeerID == 0) {
            return; // Can't guess size from peer at start of array.
        }
        sizeOfEnetPeer
            = (cast(const void*) peerInArray - cast(const void*) _host.peers)
            / peerInArray.incomingPeerID;
    }

    void disconnectLater(in PlNr toDiscon)
    {
        enet_peer_disconnect_later(plNrToPeer(toDiscon), 0);
    }
}

private class Outbox2016 : Outbox {
private:
    SendWithEnet _out; // We don't own it. We merely know the server's.

public:
    this(SendWithEnet viaWhichWeSend)
    {
        _out = viaWhichWeSend;
    }

    void sendChat(in PlNr receiv, in PlNr fromChatter, in string text)
    {
        ChatPacket chat;
        chat.header.packetID = PacketStoC.peerChatMessage;
        chat.header.plNr = fromChatter;
        chat.text = text;
        _out.send(receiv, chat.createPacket);
    }

    void sendLevelByChooser(PlNr receiv, const(ubyte[]) level, PlNr from) @nogc
    {
        struct LevelPacket {
            const(ubyte[]) _level;
            PlNr _from;
            ENetPacket* createPacket() const nothrow @nogc {
                PacketHeader header;
                header.packetID = PacketStoC.peerLevelFile;
                header.plNr = _from;
                auto ret = .createPacket(header.len + _level.length);
                header.serializeTo(ret.data[0 .. header.len]);
                ret.data[header.len .. ret.dataLength] = _level[0 .. $];
                return ret;
            }
        }
        _out.send(receiv, LevelPacket(level, from).createPacket);
    }

    void sendProfileChangeBy(in PlNr receiv, in PlNr ofWhom, in Profile full)
    {
        ProfilePacket pa;
        pa.header.packetID = PacketStoC.peerProfile;
        pa.header.plNr = ofWhom;
        pa.profile = full;
        _out.send(receiv, pa.createPacket);
    }

    void sendPly(PlNr receiv, Ply data)
    {
        _out.send(receiv, data.createPacket(PacketStoC.peerPly));
    }

    void describeRoom(in PlNr receiv, in Profile[PlNr] contents)
    {
        auto informMover = ProfileListPacket();
        informMover.header.packetID = PacketStoC.peersAlreadyInYourNewRoom;
        informMover.header.plNr = receiv;
        foreach (key, prof; contents) {
            informMover.indices ~= key;
            informMover.profiles ~= prof;
        }
        _out.send(receiv, informMover.createPacket);
    }

    void informLobbyistAboutRooms(PlNr receiv, in RoomListPacket rlp)
    {
        _out.send(receiv, rlp.createPacket);
    }

    void sendPeerEnteredYourRoom(PlNr receiv, PlNr mover, in Profile ofMover)
    {
        auto pa = ProfilePacket();
        pa.header.packetID = PacketStoC.peerJoinsYourRoom;
        pa.header.plNr = mover;
        pa.profile = ofMover;
        _out.send(receiv, pa.createPacket);
    }

    void sendPeerLeftYourRoom(PlNr receiv, PlNr mover, in Room toWhere)
    {
        auto pa = RoomChangePacket();
        pa.header.packetID = PacketStoC.peerLeftYourRoom;
        pa.header.plNr = mover;
        pa.room = toWhere;
        _out.send(receiv, pa.createPacket);
    }

    void sendPeerDisconnected(in PlNr receiv, in PlNr disconnected)
    {
        auto discon = SomeoneDisconnectedPacket();
        discon.packetID = PacketStoC.peerDisconnected;
        discon.plNr = disconnected;
        _out.send(receiv, discon.createPacket);
    }

    void startGame(in PlNr receiv, in PlNr roomOwner, in int permuLength)
    {
        auto pa = StartGameWithPermuPacket(permuLength);
        pa.header.packetID = PacketStoC.gameStartsWithPermu;
        pa.header.plNr = roomOwner;
        _out.send(receiv, pa.createPacket);
    }

    void sendMillisecondsSinceGameStart(PlNr receiv, int millis)
    {
        auto pa = MillisecondsSinceGameStartPacket();
        pa.header.packetID = PacketStoC.millisecondsSinceGameStart;
        pa.header.plNr = receiv; // doesn't matter
        pa.milliseconds = millis;
        _out.send(receiv, pa.createPacket);
    }
}
