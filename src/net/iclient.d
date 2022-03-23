module net.iclient;

import net.permu;
import net.plnr;
import net.profile;
import net.repdata;
import net.style;
import net.versioning;

interface INetClient {
    void disconnectAndDispose();
    void calc(); // call this frequently, this shovels incoming networking
                 // data into refined structs to fetch from other methods
    void sendChatMessage(string);

    @property bool connected() const pure;
    @property bool connecting() const pure;

    @property string enetLinkedVersion() const;

    @property const(Profile2022[PlNr]) profilesInOurRoom();
    @property PlNr ourPlNr() const pure;
    @property const(Profile2022) ourProfile() const pure;
    @property bool mayWeDeclareReady() const;

    // Call this when the GUI has chosen a new Lix style.
    // The GUI may update ahead of time, but what the server knows, decides.
    // Feeling is readiness, and whether we want to observe.
    @property void ourStyle(Style sty);
    @property void ourFeeling(Profile2022.Feeling feel);
    void gotoExistingRoom(Room);
    void createRoom();

    void selectLevel(const(void[])); // accepts file that's read into a buffer
    void sendPly(in Ply);

    // Register an event callback. The class who designs the callback functions
    // should display a message from the callback information. Usually, the
    // calling class wants to get profilesInOurRoom, too, to update the list
    // as a whole. The class should write one method that queries the profiles
    // from (this) and call that method in many of the callbacks here.
    @property void onConnect(void delegate());
    @property void onCannotConnect(void delegate());
    @property void onVersionMisfit(void delegate(Version serverVersion));
    @property void onConnectionLost(void delegate());
    @property void onChatMessage(void delegate(string name, string chat));
    @property void onPeerDisconnect(void delegate(string name));
    @property void onPeerJoinsRoom(void delegate(in Profile2022));
    @property void onPeerLeavesRoomTo(void delegate(string name, Room toRoom));
    @property void onPeerChangesProfile(void delegate(in Profile2022));
    @property void onWeChangeRoom(void delegate(Room toRoom));

    // Structure of arrays: The n-th room ID from the first array belongs
    // to the n-th player from the second array.
    @property void onListOfExistingRooms(void delegate(in Room[],
                                                       in Profile2022[]));
    @property void onLevelSelect(void delegate(string name, in ubyte[] data));
    @property void onGameStart(void delegate(Permu));
    @property void onPeerSendsPly(void delegate(Ply));

    // The server tells us how many milliseconds have passed.
    // The client adds his networking lag to that value, then calls the
    // delegate with the thereby-increased value of milliseconds.
    @property void onMillisecondsSinceGameStart(void delegate(int));
}
