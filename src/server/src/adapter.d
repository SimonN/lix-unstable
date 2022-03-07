module net.server.adapter;

/*
 * net.server.adapter: Concrete Inboxes and Outboxes that NetServer will use.
 */

import derelict.enet.enet;
import net.enetglob;
import net.plnr;
import net.repdata;
import net.server.hotel;
import net.server.outbox;
import net.packetid;
import net.permu;
import net.profile;
import net.structs;

// ############################################################################
// Client to Server: ##########################################################
// ############################################################################

/*
 * Inbox don't have receiveHello.
 * Reason: The server should handle Hello and, based on that, choose the
 * correct Inbox (adapter) for all future packets after Hello.
 */
interface Inbox {
    void receiveRoomChange(in PlNr from, in ENetPacket* got);
    void receiveCreateRoom(in PlNr from, in ENetPacket* got);
    void receiveProfileChange(in PlNr from, in ENetPacket* got);
    void receiveChat(in PlNr from, in ENetPacket* got);
    void receiveLevel(in PlNr from, in ENetPacket* got);
    void receivePly(in PlNr from, in ENetPacket* got);
}

/*
 * Convention: When we make a struct from the packet data, this struct contains
 * a header, but we don't trust header.plNr. To see who sent this
 * packet, we always rely on (PlNr from) passed by our caller, the NetServer.
 */
class Inbox2016 : Inbox {
private:
    Hotel* _hotel; // We don't own it. We merely know it and forward to it.

public:
    this(Hotel* thatWeShallForwardTo)
    {
        _hotel = thatWeShallForwardTo;
    }

    void receiveRoomChange(in PlNr from, in ENetPacket* got)
    {
        _hotel.movePlayer(from, RoomChangePacket(got).room);
    }

    void receiveCreateRoom(in PlNr from, in ENetPacket* got)
    {
        _hotel.movePlayer(from, _hotel.firstFreeRoomElseLobby());
    }

    void receiveProfileChange(in PlNr from, in ENetPacket* got)
    {
        _hotel.changeProfile(from, ProfilePacket(got).profile);
    }

    void receiveChat(in PlNr from, in ENetPacket* got)
    {
        _hotel.broadcastChat(from, ChatPacket(got).text);
    }

    void receiveLevel(in PlNr from, in ENetPacket* got)
    {
        if (got.dataLength < 2) {
            return; // Too short for even an empty level.
        }
        _hotel.receiveLevel(from, got.data[2 .. got.dataLength]);
    }

    void receivePly(in PlNr from, in ENetPacket* got)
    {
        if (got.dataLength != Ply.len) {
            return;
        }
        auto ply = Ply(got);
        ply.player = from; // Don't trust. The server decides who sent it!
        _hotel.receivePly(ply);
    }
}

// ############################################################################
// Server to Client: ##########################################################
// ############################################################################

interface SendWithEnet {
    void send(in PlNr receiv, ENetPacket* what) @nogc; // Then owns the packet.
    void disconnectLater(in PlNr toDiscon);
}

class Outbox_0_9_x : Outbox {
private:
    SendWithEnet _out; // We don't own it. We merely know the server's.

public:
    this(SendWithEnet viaWhichWeSend) { _out = viaWhichWeSend; }
    mixin sendChat2016;
    mixin sendLevel2016;
    mixin sendProfile2016;
    mixin sendPly2016;
    mixin describeRoom2016;
    mixin informLobbyist2016;
    mixin sendPeerEnteredYourRoom2016;
    mixin sendPeerLeftYourRoom2016;
    mixin sendPeerDisconnected2016;
    mixin startGame2016;
    mixin sendMilliseconds2016;
}

alias Outbox_0_10_x = Outbox_0_9_x;

private mixin template sendChat2016() {
    void sendChat(in PlNr receiv, in PlNr fromChatter, in string text)
    {
        ChatPacket chat;
        chat.header.packetID = PacketStoC.peerChatMessage;
        chat.header.plNr = fromChatter;
        chat.text = text;
        _out.send(receiv, chat.createPacket);
    }
}

private mixin template sendLevel2016() {
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
}

private mixin template sendProfile2016() {
    void sendProfileChangeBy(in PlNr receiv, in PlNr ofWhom, in Profile full)
    {
        ProfilePacket pa;
        pa.header.packetID = PacketStoC.peerProfile;
        pa.header.plNr = ofWhom;
        pa.profile = full;
        _out.send(receiv, pa.createPacket);
    }
}

private mixin template sendPly2016() {
    void sendPly(PlNr receiv, Ply data)
    {
        _out.send(receiv, data.createPacket(PacketStoC.peerPly));
    }
}

private mixin template describeRoom2016() {
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
}

private mixin template informLobbyist2016() {
    void informLobbyistAboutRooms(PlNr receiv, in RoomListPacket rlp)
    {
        _out.send(receiv, rlp.createPacket);
    }
}

private mixin template sendPeerEnteredYourRoom2016() {
    void sendPeerEnteredYourRoom(PlNr receiv, PlNr mover, in Profile ofMover)
    {
        auto pa = ProfilePacket();
        pa.header.packetID = PacketStoC.peerJoinsYourRoom;
        pa.header.plNr = mover;
        pa.profile = ofMover;
        _out.send(receiv, pa.createPacket);
    }
}

private mixin template sendPeerLeftYourRoom2016() {
    void sendPeerLeftYourRoom(PlNr receiv, PlNr mover, in Room toWhere)
    {
        auto pa = RoomChangePacket();
        pa.header.packetID = PacketStoC.peerLeftYourRoom;
        pa.header.plNr = mover;
        pa.room = toWhere;
        _out.send(receiv, pa.createPacket);
    }
}

private mixin template sendPeerDisconnected2016() {
    void sendPeerDisconnected(in PlNr receiv, in PlNr disconnected)
    {
        auto discon = SomeoneDisconnectedPacket();
        discon.packetID = PacketStoC.peerDisconnected;
        discon.plNr = disconnected;
        _out.send(receiv, discon.createPacket);
    }
}

private mixin template startGame2016() {
    void startGame(in PlNr receiv, in PlNr roomOwner, in int permuLength)
    {
        auto pa = StartGameWithPermuPacket(permuLength);
        pa.header.packetID = PacketStoC.gameStartsWithPermu;
        pa.header.plNr = roomOwner;
        _out.send(receiv, pa.createPacket);
    }
}

private mixin template sendMilliseconds2016() {
    void sendMillisecondsSinceGameStart(PlNr receiv, int millis)
    {
        auto pa = MillisecondsSinceGameStartPacket();
        pa.header.packetID = PacketStoC.millisecondsSinceGameStart;
        pa.header.plNr = receiv; // doesn't matter
        pa.milliseconds = millis;
        _out.send(receiv, pa.createPacket);
    }
}
