module net.server.adapter;

/*
 * net.server.adapter: Concrete Inboxes and Outboxes that NetServer will use.
 */
import std.array;
import std.algorithm;

import derelict.enet.enet;
import net.enetglob;
import net.header;
import net.plnr;
import net.repdata;
import net.server.hotel;
import net.server.outbox;
import net.packetid;
import net.permu;
import net.profile;
import net.structs;
import net.versioning;

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
        import net.versioning;
        _hotel.changeProfileButKeepVersion(from, ProfilePacket2016(got)
            .profile.to2022with(Version(0, 7, 77)) // We ignore 2016 versions.
        );
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
    mixin commonOutboxMethods;
    mixin informLobbyist2016;
    mixin describePeers2016;
    mixin sendPeerEnteredYourRoom2016;
    mixin sendProfile2016;
}

class Outbox_0_10_x : Outbox {
private:
    SendWithEnet _out; // We don't own it. We merely know the server's.

public:
    this(SendWithEnet viaWhichWeSend) { _out = viaWhichWeSend; }
    mixin commonOutboxMethods;
    mixin informLobbyist2022;
    mixin describePeers2022;
    mixin sendPeerEnteredYourRoom2022;
    mixin sendProfile2022;
}

private mixin template commonOutboxMethods() {
    void sendChat(in PlNr receiv, in PlNr fromChatter, in string text)
    {
        ChatPacket chat;
        chat.header.packetID = PacketStoC.peerChatMessage;
        chat.header.plNr = fromChatter;
        chat.text = text;
        _out.send(receiv, chat.createPacket);
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

    void sendLevelByChooser(PlNr receiv, const(ubyte[]) level, PlNr from) @nogc
    {
        struct LevelPacket {
            const(ubyte[]) _level;
            PlNr _from;
            ENetPacket* createPacket() const nothrow @nogc {
                PacketHeader2016 header;
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

    void startGame(in PlNr receiv, in PlNr roomOwner, in int permuLength)
    {
        auto pa = StartGameWithPermuPacket(permuLength);
        pa.header.packetID = PacketStoC.gameStartsWithPermu;
        pa.header.plNr = roomOwner;
        _out.send(receiv, pa.createPacket);
    }

    void sendPly(PlNr receiv, Ply data)
    {
        _out.send(receiv, data.createPacket(PacketStoC.peerPly));
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

private mixin template informLobbyist2016() {
    void informLobbyistAboutRooms(
        in PlNr receiv,
        in Version ofReceiver,
        in RoomListPacket2022 rlp)
    {
        RoomListPacket2016 old;
        old.header.packetID = PacketStoC.listOfExistingRooms;
        old.header.plNr = receiv;
        foreach (e; rlp.arr) {
            if (! e.owner.clientVersion.compatibleWith(ofReceiver)) {
                /*
                 * Don't show un-enterable rooms to 2016 protocol users;
                 * they expect all shown rooms to be enterable.
                 */
                continue;
            }
            old.indices ~= e.room;
            old.profiles ~= e.owner.to2016with(e.room);
        }
        _out.send(receiv, old.createPacket);
    }
}

private mixin template informLobbyist2022() {
    void informLobbyistAboutRooms(
        in PlNr receiv,
        in Version ofReceiver_LegacyFor2016toFilterIncompatibleRooms,
        in RoomListPacket2022 rlp)
    {
        _out.send(receiv, rlp.createPacket);
    }
}

private mixin template describePeers2016() {
    void describeLobbyists(
        in PlNr receiv,
        in Profile2022[PlNr] contents,
    ) {
        describePeersInRoom(receiv, Room(0), contents, receiv);
    }

    void describePeersInRoom(
        in PlNr receiv,
        in Room here,
        in Profile2022[PlNr] contents,
        in PlNr ownerOfHere_unusedIn2016,
    ) {
        auto informMover = ProfileListPacket2016();
        informMover.header.packetID = PacketStoC.peersAlreadyInYourNewRoom;
        informMover.header.plNr = receiv;
        foreach (key, prof; contents) {
            informMover.indices ~= key;
            informMover.profiles ~= prof.to2016with(here);
        }
        _out.send(receiv, informMover.createPacket);
    }
}

private mixin template describePeers2022() {
    void describeLobbyists(
        in PlNr receiv,
        in Profile2022[PlNr] contents,
    ) {
        auto informMover = PeersInRoomPacket2022();
        informMover.setHeader(PacketStoC.peersAlreadyInYourNewRoom,
            Room(0), receiv);
        foreach (key, prof; contents) {
            PeerInRoomEntry2022 entry;
            entry.plnr = key;
            entry.isOwner = false;
            entry.profile = prof;
            informMover.arr ~= entry;
        }
        _out.send(receiv, informMover.createPacket);
    }

    void describePeersInRoom(
        in PlNr receiv,
        in Room here,
        in Profile2022[PlNr] contents,
        in PlNr ownerOfHere)
    {
        auto informMover = PeersInRoomPacket2022();
        informMover.setHeader(PacketStoC.peersAlreadyInYourNewRoom,
            here, receiv);
        foreach (key, prof; contents) {
            PeerInRoomEntry2022 entry;
            entry.plnr = key;
            entry.isOwner = (key == ownerOfHere);
            entry.profile = prof;
            informMover.arr ~= entry;
        }
        _out.send(receiv, informMover.createPacket);
    }
}

private mixin template sendPeerEnteredYourRoom2016() {
    void sendPeerEnteredYourRoom(
        in PlNr receiv,
        in Room here,
        in PlNr mover,
        in Profile2022 ofMover)
    {
        auto pa = ProfilePacket2016();
        pa.header.packetID = PacketStoC.peerJoinsYourRoom;
        pa.header.plNr = mover;
        pa.profile = ofMover.to2016with(here);
        _out.send(receiv, pa.createPacket);
    }
}

private mixin template sendPeerEnteredYourRoom2022() {
    void sendPeerEnteredYourRoom(
        in PlNr receiv,
        in Room here,
        in PlNr mover,
        in Profile2022 ofMover)
    {
        auto pa = ProfilePacket2022();
        pa.setHeader(PacketStoC.peerJoinsYourRoom, here, mover);
        pa.neck = ofMover;
        _out.send(receiv, pa.createPacket);
    }
}

private mixin template sendProfile2016() {
    void sendProfileChangeBy(
        in PlNr receiv,
        in Room here,
        in PlNr ofWhom,
        in Profile2022 full)
    {
        ProfilePacket2016 pa;
        pa.header.packetID = PacketStoC.peerProfile;
        pa.header.plNr = ofWhom;
        pa.profile = full.to2016with(here);
        _out.send(receiv, pa.createPacket);
    }
}

private mixin template sendProfile2022() {
    void sendProfileChangeBy(
        in PlNr receiv,
        in Room here,
        in PlNr ofWhom,
        in Profile2022 full)
    {
        ProfilePacket2022 pa;
        pa.setHeader(PacketStoC.peerProfile, here, ofWhom);
        pa.neck = full;
        _out.send(receiv, pa.createPacket);
    }
}
