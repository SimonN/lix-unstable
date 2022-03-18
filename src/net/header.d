module net.header;

/*
 * Binary Message Headers:
 * How packet ID and PlNr (and maybe Room) aggregate  into a binary message
 * packet header (PacketHeader2016 or PacketHeader2022)
 * that will be the first several bytes of the many-byte binary messages.
 */

import std.bitmanip;
import std.exception;
import derelict.enet.enet;

import net.enetglob;
import net.plnr;

// ####################################################################### 2022

private mixin template CommonHeaderFields() {
    enum len = 16;
    ubyte packetId;
    PlNr subject; // Somebody else. Or the recipient if the array holds plnrs.
    Room subjectsRoom;
}

struct NonarrayPacketHeader2022 {
    mixin CommonHeaderFields;

    void serializeTo(ref ubyte[len] buf) const pure nothrow @nogc
    {
        buf[0] = packetId;
        buf[1] = 0; // Reserved for a future sub-packetID. Unused as of 2022.
        buf[2 .. 4] = subject.nativeToBigEndian!short;
        buf[4 .. 6] = subjectsRoom.nativeToBigEndian!short;
        buf[6 .. 8] = len.nativeToBigEndian!short;
        buf[8 .. 12] = 0; // No array elements. The nonarray data starts at 16.
        buf[12 .. 16] = 0; // Reserved for a future int, possibly per-packetID.
    }

    public this(ref const(ubyte[len]) buf) pure nothrow @nogc
    {
        packetId = buf[0];
        subject = PlNr(0xFF & bigEndianToNative!short(buf[2 .. 4]));
        subjectsRoom = Room(0xFF & bigEndianToNative!short(buf[4 .. 6]));
    }
}

struct ArrayPacketHeader2022 {
    mixin CommonHeaderFields;
    /*
     * (numFields) is >= 0. It's legal to send an empty array.
     * arr[0] starts at (offsetField0) from the start of the packet.
     * That (offsetField0) must be >= (PacketHeader2022.len)
     * and is usually ==; the packet is invalid if it is <.
     *
     * If (numFields) >= 1, then:
     * For receipient to correctly index arr[1], arr[2], ..., he shall use
     * (bytesPerField). I.e.:
     *
     *      For 0 <= i < numFields,
     *      arr[i] starts at   (packet + offsetField0) +   i   * bytesPerField,
     *      arr[i] ends before (packet + offsetField0) + (i+1) * bytesPerField.
     *      You can use this.offsetOfField(i).
     *
     * The recipient shall _not_ rely on the part of the packet that
     * starts at packet (offsetField0) and goes to the packet length in bytes,
     * dividing it by numFields, even though both of these possibilities
     * should match. Recipients may consider packets invalid if those don't
     * match.
     *
     * Recipients must always assume that the sender made bytesPerField
     * larger than the recipient needs, and thus the packet also becomes
     * larger by (the excess per field times numFields). Recipients shall
     * index according to bytesPerField and ignore any excess bytes at
     * end of each field. This is to make the packet format future-proof
     * when newer versions need longer structs.
     *
     * Recipients may reject packets with smaller bytesPerField than they need.
     */
    short offsetField0 = len;
    short numFields = 1;
    short bytesPerField;

    int offsetOfField(in int index) const pure @safe
    {
        enforce(index >= 0);
        enforce(index <= numFields);
        return offsetField0 + index * bytesPerField;
    }

    void serializeTo(ref ubyte[len] buf) const pure nothrow @nogc
    {
        buf[0] = packetId;
        buf[1] = 0; // Reserved for a future sub-packetID. Unused as of 2022.
        buf[2 .. 4] = subject.nativeToBigEndian!short;
        buf[4 .. 6] = subjectsRoom.nativeToBigEndian!short;
        buf[6 .. 8] = offsetField0.nativeToBigEndian!short;
        buf[8 .. 10] = numFields.nativeToBigEndian!short;
        buf[10 .. 12] = bytesPerField.nativeToBigEndian!short;
        buf[12 .. 16] = 0; // Reserved for a future int, possibly per-packetID.
    }

    this(ref const(ubyte[len]) buf) pure nothrow @nogc
    {
        packetId = buf[0];
        // buf[1] is reserved, see serializeTo.
        subject = PlNr(0xFF & bigEndianToNative!short(buf[2 .. 4]));
        subjectsRoom = Room(0xFF & bigEndianToNative!short(buf[4 .. 6]));
        offsetField0 = bigEndianToNative!short(buf[6 .. 8]);
        numFields = bigEndianToNative!short(buf[8 .. 10]);
        bytesPerField = bigEndianToNative!short(buf[10 .. 12]);
        // buf[12 .. 16] is reserved, see serializeTo.
    }
}

template isSerializable(ElementType) {
    enum bool isSerializable = is(ElementType == struct)
        && is(typeof(ElementType.len) : int)
        && is(typeof(ElementType.serializeTo));
}

struct ArrayPacket(ubyte packetId, ElementType)
    if (isSerializable!ElementType)
{
public:
    PlNr subject;
    Room subjectsRoom;
    ElementType[] arr;

    int len() const pure nothrow @safe @nogc
    {
        return ArrayPacketHeader2022.len
            + (arr.length & 0x7FFF) * ElementType.len;
    }

    ArrayPacketHeader2022 header() const pure nothrow @safe @nogc
    {
        ArrayPacketHeader2022 ret;
        ret.packetId = packetId;
        ret.subject = subject;
        ret.subjectsRoom = subjectsRoom;
        ret.offsetField0 = ret.len;
        ret.numFields = arr.length & 0x7FFF;
        ret.bytesPerField = ElementType.len & 0x7FFF;
        return ret;
    }

    void setSubjectInHeader(in PlNr subj, in Room ofSubject)
    {
        subject = subj;
        subjectsRoom = ofSubject;
    }

    this(in ubyte[] buf) pure
    {
        arr = [];
        enforce(buf.length >= ArrayPacketHeader2022.len);
        auto hea = ArrayPacketHeader2022(buf[0 .. ArrayPacketHeader2022.len]);
        enforce(hea.packetId == packetId);

        for (int i = 0; i < hea.numFields
            && hea.offsetOfField(i+1) <= buf.length; ++i
        ) {
            arr ~= ElementType(buf[hea.offsetOfField(i)
                                .. hea.offsetOfField(i+1)]);
        }
        subject = hea.subject;
        subjectsRoom = hea.subjectsRoom;
    }

    void serializeTo(ubyte[] buf) const pure
    {
        enforce(buf.length >= len);
        const hea = header();
        hea.serializeTo(buf[0 .. hea.len]);
        for (int i = 0; i < arr.length; ++i) {
            ubyte[ElementType.len] temp;
            arr[i].serializeTo(temp);
            buf[hea.offsetOfField(i) .. hea.offsetOfField(i+1)] = temp;
        }
    }

    ENetPacket* createPacket() const
    {
        auto ret = .createPacket(len);
        serializeTo(ret.data[0 .. len]);
        return ret;
    }
}
