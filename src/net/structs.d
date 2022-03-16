module net.structs;

/* The client and server exchange messages via enet. These messages are
 * manually serialized and deserialized structs, different structs for
 * different messages.
 *
 * Manual memory management: When a struct returns an ENetPacket*, then
 * it has asked enet to allocate the packet. When you send or broadcast
 * that packet, enet will deallocate it for you.
 *
 * Structs that read or write from bare buffers don't allocate.
 */

import std.algorithm;
import std.bitmanip;
import std.conv;
import std.exception;
import std.range;
import std.string;

import derelict.enet.enet;

import net.enetglob;
import net.header;
import net.packetid;
import net.style;
import net.plnr;
import net.profile;
import net.versioning;

struct PacketHeader2016 {
    enum len = 2;
    ubyte packetID;
    PlNr plNr;

    this(ref const(ubyte[len]) buf) nothrow @nogc
    {
        packetID = buf[0];
        plNr = PlNr(buf[1]);
    }

    void serializeTo(ref ubyte[len] buf) const nothrow @nogc
    {
        buf[0] = packetID;
        buf[1] = plNr;
    }

    ENetPacket* createPacket() const nothrow @nogc
    {
        auto ret = .createPacket(len);
        serializeTo(ret.data[0 .. len]);
        return ret;
    }
}

struct SomeoneDisconnectedPacket {
    PacketHeader2016 header;
    alias header this;

    this(const(ENetPacket*) p)
    {
        enforce(p.dataLength >= PacketHeader2016.len);
        header = PacketHeader2016(p.data[0 .. PacketHeader2016.len]);
    }
}

// Give this function a range with all profiles from the same room
bool mayRoomDeclareReady(R)(R range)
    if (isForwardRange!R && is (ElementType!R : const (Profile)))
{
    // all must be in same room that isn't the lobby
    if (range.any!(pro => pro.room != range.front.room || pro.room == 0))
        return false;
    return range.walkLength >= 2
        && range.any!(pro => pro.feeling != Profile.Feeling.observing);
}

struct HelloPacket {
    enum len = header.len + fromVersion.len + profile.len;
    PacketHeader2016 header;
    Version fromVersion;
    Profile profile;

    ENetPacket* createPacket() const nothrow @nogc
    in { assert (header.packetID == PacketCtoS.hello); }
    out (ret) { assert (ret.data[0] == PacketCtoS.hello); }
    do {
        auto ret = .createPacket(len);
        header.serializeTo(ret.data[0 .. header.len]);
        fromVersion.serializeTo(ret.data[header.len
                                      .. header.len + fromVersion.len]);
        profile.serializeTo(ret.data[len - profile.len .. len]);
        return ret;
    }

    this(const(ENetPacket*) p)
    {
        // In <= 0.9.42, we had here: enforce(p.dataLength == len), not >=
        enforce(p.dataLength >= len);
        header = PacketHeader2016(p.data[0 .. header.len]);
        enforce(header.packetID == PacketCtoS.hello);
        fromVersion = Version(p.data[header.len .. header.len + Version.len]);
        profile = Profile(p.data[len - profile.len .. len]);
        /*
         * If the client sent a longer packet, we ignore what comes at
         * >= HelloPacket.len. Future server versions might interpret it.
         */
    }
}

struct HelloAnswerPacket {
    enum len = header.len + serverVersion.len;
    PacketHeader2016 header;
    Version serverVersion;

    ENetPacket* createPacket() const nothrow @nogc
    {
        auto ret = .createPacket(len);
        header.serializeTo(ret.data[0 .. header.len]);
        serverVersion.serializeTo(ret.data[len - serverVersion.len .. len]);
        return ret;
    }

    this(const(ENetPacket*) p)
    {
        enforce(p.dataLength == len);
        header = PacketHeader2016(p.data[0 .. header.len]);
        serverVersion = Version(p.data[len - serverVersion.len .. len]);
    }
}

unittest {
    import net.enetglob;
    initializeEnet();
    scope (exit)
        deinitializeEnet();

    HelloAnswerPacket a;
    a.serverVersion = Version(1, 23, 456);
    ENetPacket* p = a.createPacket;
    auto b = HelloAnswerPacket(p);
    assert (b.serverVersion == a.serverVersion);
    assert (b.serverVersion.minor == 23);
}

struct ProfilePacket {
    enum len = header.len + profile.len;
    PacketHeader2016 header;
    Profile profile;

    ENetPacket* createPacket() const nothrow @nogc
    {
        auto ret = .createPacket(len);
        header.serializeTo(ret.data[0 .. header.len]);
        profile.serializeTo(ret.data[len - profile.len .. len]);
        return ret;
    }

    this(const(ENetPacket*) p)
    {
        enforce(p.dataLength == len);
        header = PacketHeader2016(p.data[0 .. header.len]);
        profile = Profile(p.data[len - profile.len .. len]);
    }
}

// ############################################################### list packets

alias ProfileListPacket2016 = ListPacket2016!PlNr;
alias RoomListPacket2016 = ListPacket2016!Room;

struct ListPacket2016(Index)
    if (is (Index == PlNr) || is (Index == Room))
{
    PacketHeader2016 header;
    Index[] indices; // structure of arrays, indices[i] belongs to profiles[i]
    Profile2016[] profiles;

    @property int len() const nothrow @nogc
    {
        int numProfiles = profiles.length & 0x7FFF;
        return header.len + (Index.len + Profile2016.len) * numProfiles;
    }

    private @property int mid() const nothrow @nogc
    {
        return header.len + Index.len * (indices.length & 0x7FFF);
    }

    ENetPacket* createPacket() const nothrow @nogc
    out (ret) {
        assert (indices.length == 0 || ret.data[header.len] == indices[0]);
    }
    do {
        auto ret = .createPacket(len);
        header.serializeTo(ret.data[0 .. header.len]);

        foreach (i, Index; indices) {
            static assert (Index.len == 1);
            ret.data[header.len + i] = Index;
        }
        assert (indices.length == 0 || ret.data[header.len] == indices[0]);
        foreach (i, profile; profiles) {
            // profile.serializeTo expects the slice length at compile-time.
            // I don't know how to create a fixed-length D array from a pointer
            // and the length, so I do it with this otherwise-unecessary copy.
            ubyte[Profile2016.len] temp;
            profile.serializeTo(temp);
            ret.data[mid + Profile2016.len * i
                ..   mid + Profile2016.len * (i+1)] = temp[];
        }
        return ret;
    }

    this(const(ENetPacket*) p)
    out { assert (indices.length == profiles.length); }
    do {
        enforce((p.dataLength - header.len) % (Profile2016.len + Index.len) == 0);
        header = PacketHeader2016(p.data[0 .. header.len]);
        indices.length = (p.dataLength - header.len)
                        / (Profile2016.len + Index.len);
        foreach (i, ref oneIndex; indices) {
            static assert (oneIndex.len == 1);
            oneIndex = Index(p.data[header.len + i]);
        }
        profiles.length = indices.length;
        foreach (i, ref profile; profiles) {
            ubyte[Profile2016.len] temp = p.data[mid + Profile2016.len * i
                                              .. mid + Profile2016.len * (i+1)];
            profile = Profile2016(temp);
        }
    }
}

unittest {
    import net.enetglob;
    initializeEnet();
    scope (exit)
        deinitializeEnet();

    // 2016
    {
        ProfileListPacket2016 list;
        list.indices = [ PlNr(80), PlNr(81), PlNr(82) ];
        list.profiles = [ Profile(), Profile(), Profile() ];
        list.profiles[1].name = "Hello";

        auto packet = list.createPacket;
        assert (packet.data[list.header.len + 0] == 80);
        assert (packet.data[list.header.len + 1] == 81);

        auto anotherList = ProfileListPacket2016(packet);
        assert (anotherList.profiles.length == 3);
        assert (anotherList.indices[1] == 81);
        assert (anotherList.profiles[1].name == "Hello");
    }
    // 2022
    {
        RoomListEntry2022 createEntry(in Room r, in int i, in string name) {
            RoomListEntry2022 ret;
            ret.room = r;
            ret.numInhabitants = i;
            ret.owner = Profile2022();
            ret.owner.name = name;
            return ret;
        }
        RoomListPacket2022 before;
        before.arr ~= createEntry(Room(3), 33, "Hello");
        before.arr ~= createEntry(Room(5), 55, "World");

        auto packet = before.createPacket;
        auto after = RoomListPacket2022(packet.data[0 .. packet.dataLength]);
        assert (after.arr.length == 2);
        assert (after.arr[0].owner.name == "Hello");
        assert (after.arr[1].owner.name == "World");
        assert (after.arr[1].room == Room(5));
        assert (after.arr[1].numInhabitants == 55);
    }
}

alias RoomListPacket2022
    = ArrayPacket!(PacketStoC.listOfExistingRooms, RoomListEntry2022);

struct RoomListEntry2022 {
    Room room;
    int numInhabitants;
    Profile2022 owner;

    enum int len = 8 + owner.len;

    this(in ubyte[] buf) pure {
        enforce (buf.length >= len);
        room = Room(0xFF & buf[0 .. 2].bigEndianToNative!short);
        numInhabitants = buf[2 .. 4].bigEndianToNative!short;
        // buf[4 .. 8] unused, they're always 0.
        owner = Profile2022(buf[8 .. buf.length]);
    }

    void serializeTo(ref ubyte[len] buf) const pure nothrow @nogc
    {
        buf[0 .. 2] = nativeToBigEndian!short(room);
        buf[2 .. 4] = nativeToBigEndian!short(numInhabitants & 0x7FFF);
        buf[4 .. 8] = 0; // Unused, reserved.
        owner.serializeTo(buf[8 .. len]);
    }
}

// ######################################################## end of list packets

struct RoomChangePacket {
    enum len = header.len + Room.sizeof;
    PacketHeader2016 header;
    Room room;

    ENetPacket* createPacket() const nothrow @nogc
    {
        auto ret = .createPacket(len);
        header.serializeTo(ret.data[0 .. header.len]);
        static assert (room.sizeof == 1);
        ret.data[header.len] = room;
        return ret;
    }

    this(const(ENetPacket*) p)
    {
        enforce(p.dataLength == len);
        header = PacketHeader2016(p.data[0 .. header.len]);
        room = Room(p.data[header.len]);
    }
}

struct ChatPacket {
    PacketHeader2016 header;
    string text;

    static assert (netChatMaxLen <= 0xFFFF);
    int len() const pure nothrow @safe @nogc
    {
        return header.len
            + (min(netChatMaxLen & 0xFFFF, text.length & 0xFFFF) & 0xFFFF)
            + 1; // Terminating nullbyte
    }

    ENetPacket* createPacket() const nothrow @nogc
    {
        auto ret = .createPacket(len);
        header.serializeTo(ret.data[0 .. header.len]);
        ret.data[header.len .. len] = '\0';
        foreach (int i; 0 .. (len - header.len - 1)) {
            ret.data[header.len + i] = text[i];
        }
        ret.data[len - 1] = '\0';
        return ret;
    }

    this(const(ENetPacket*) p)
    {
        enforce(p.dataLength >= 3);
        header = PacketHeader2016(p.data[0 .. header.len]);
        if (p.data[p.dataLength - 1] == '\0')
            text = fromStringz(cast (char*) (p.data + header.len)).idup;
    }
}

unittest {
    import net.enetglob;
    initializeEnet();
    scope (exit)
        deinitializeEnet();

    ChatPacket chat;
    chat.text = "Hello";
    assert (chat.len == 2 + 5 + 1);

    auto p = chat.createPacket();
    assert (p.dataLength == chat.len);

    const decoded = ChatPacket(p);
    enet_packet_destroy(p);
    assert (decoded.text == chat.text);
    assert (decoded.len == chat.len);
}

struct MillisecondsSinceGameStartPacket {
    PacketHeader2016 header;
    int milliseconds;

    enum len = header.len + milliseconds.sizeof;

    ENetPacket* createPacket() const nothrow @nogc
    {
        auto ret = .createPacket(len);
        header.serializeTo(ret.data[0 .. header.len]);
        ret.data[header.len .. header.len + milliseconds.sizeof]
            = nativeToBigEndian!int(milliseconds);
        return ret;
    }

    this(const(ENetPacket*) p)
    {
        enforce(p.dataLength >= len);
        header = PacketHeader2016(p.data[0 .. header.len]);
        milliseconds = bigEndianToNative!int(
            p.data[header.len .. header.len + milliseconds.sizeof]);
    }
}
