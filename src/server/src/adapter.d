module net.server.inbox;

import derelict.enet.enet;
import net.plnr;
import net.repdata;
import net.server.hotel;
import net.structs;

interface Inbox {
    void receiveRoomChange(in PlNr from, in ENetPacket* got);
    void receiveCreateRoom(in PlNr from, in ENetPacket* got);
    void receiveProfileChange(in PlNr from, in ENetPacket* got);
    void receiveChat(in PlNr from, in ENetPacket* got);
    void receiveLevel(in PlNr from, in ENetPacket* got);
    void receivePly(in PlNr from, in ENetPacket* got);
    /*
     * We don't have receiveHello.
     * Reason: The server should handle Hello and, based on that, choose the
     * correct adapter for all future packets after Hello.
     */
}

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
