module net.client.adapter;

import derelict.enet.enet;

import net.enetglob;
import net.packetid;
import net.plnr;
import net.profile;
import net.structs;
import net.versioning;

package:

interface ClientAdapter {
    ProfilePacket2022 receiveProfilePacket(in ubyte[]) const;

    void sendOurUpdatedProfile(ENetPeer* serv, in Profile2022 wish,
        in PlNr ourPlnr, in Room ourRoom) const;

    static ClientAdapter factory(in Version v)
    {
        if (v.compatibleWith(Version(0, 9, 0))) {
            return new CliAdp_0_9_x;
        }
        return new CliAdp_0_10_x;
    }
}

class CliAdp_0_9_x : ClientAdapter {
    ProfilePacket2022 receiveProfilePacket(in ubyte[] got) const
    {
        const pkg = ProfilePacket2016(got);
        ProfilePacket2022 ret;
        ret.packetId = pkg.header.packetID;
        ret.subject = pkg.header.plNr;
        ret.subjectsRoom = pkg.profile.room;
        /*
         * Insert the received profile into our list.
         * Hack in the 2016 client: We assume that everybody else has our
         * version because the server doesn't tell us our version.
         * The server will tell 2022 clients the correct remote client version.
         */
        ret.neck = pkg.profile.to2022with(gameVersion);
        return ret;
    }

    void sendOurUpdatedProfile(
        ENetPeer* serv,
        in Profile2022 wish,
        in PlNr ourPlnr,
        in Room ourRoom,
    ) const
    {
        ProfilePacket2016 pkg;
        pkg.header.packetID = PacketCtoS.myProfile;
        pkg.header.plNr = ourPlnr;
        pkg.profile = wish.to2016with(ourRoom);
        pkg.enetSendTo(serv);
    }
}

class CliAdp_0_10_x : ClientAdapter {
    ProfilePacket2022 receiveProfilePacket(in ubyte[] got) const
    {
        return ProfilePacket2022(got);
    }

    void sendOurUpdatedProfile(
        ENetPeer* serv,
        in Profile2022 wish,
        in PlNr ourPlnr,
        in Room ourRoom,
    ) const
    {
        ProfilePacket2022 pkg;
        pkg.packetId = PacketCtoS.myProfile;
        pkg.subject = ourPlnr;
        pkg.subjectsRoom = ourRoom;
        pkg.neck = wish;
        pkg.enetSendTo(serv);
    }
}
