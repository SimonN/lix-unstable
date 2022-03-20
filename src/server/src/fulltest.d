module net.server.fulltest;

/*
 * Full-fledged client-server system test. We create a server and have him
 * listen on the real operating system's port 22934 (the default Lix port).
 * You can't run a server daemon while you're running this test.
 *
 * We create several clients and have them connect to the server via port
 * 22934.
 */

version (unittest):

import core.thread;
import core.time;

import std.algorithm;

import net.server.server;
import net.client;
import net.style;
import net.versioning;

unittest {
    FullTest fulltest;
    fulltest.setup();
    fulltest.colorToYellow();
    fulltest.teardown();
}

private struct FullTest {
private:
    NetServer _srv;
    NetClient _cliA;
    NetClient _cliB;

public:
    enum thePort = 22934;

    void setup()
    {
        assert (_srv is null, "Don't setup twice.");
        // Server will initialize enet on new, deinitialize on its dispose().
        _srv = new NetServer(thePort);

        _cliA = new NetClient(NetClientCfg("localhost", thePort,
            Version(0, 9, 997), "A", Style.orange));
        await("Client A connects to server", () { return _cliA.connected; });
        _cliB = new NetClient(NetClientCfg("localhost", thePort,
            Version(0, 9, 998), "B", Style.green));
        await("Client B connects to server", () { return _cliB.connected; });
    }

    void teardown()
    {
        assert (_srv, "Don't teardown twice.");
        if (_cliA) {
            _cliA.disconnectAndDispose();
            _cliA = null;
        }
        if (_cliB) {
            _cliB.disconnectAndDispose();
            _cliB = null;
        }
        _srv.dispose(); // This deinitializes enet.
        _srv = null;
    }

    void colorToYellow()
    {
        assert (_cliA.connected);
        assert (_cliB.connected);
        assert (_cliA.ourProfile.name == "A");
        assert (_cliA.ourProfile.style == Style.orange);
        await("Client B got A's initial orange", () {
            return _cliB.profilesInOurRoom.byValue.canFind!(prof
                => prof.style == Style.orange);
        });
        _cliA.ourStyle = Style.yellow;
        await("Client A style: orange -> yellow", () {
            return _cliA.ourProfile.style == Style.yellow
                && _cliB.profilesInOurRoom.byValue.canFind!(prof
                    => prof.style == Style.yellow);
        });
    }

private:
    void await(in string testName, bool delegate() successCondition)
    {
        const start = MonoTime.currTime;
        while (! successCondition()) {
            if (MonoTime.currTime > start + dur!"msecs"(500)) {
                throw new Exception("Timeout during: " ~ testName);
            }
            assert (_srv);
            _srv.calc();
            if (_cliA) { _cliA.calc(); }
            if (_cliB) { _cliB.calc(); }
            Thread.sleep(dur!"msecs"(1));
        }
    }
}
