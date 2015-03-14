module lix.lixxie;

import std.algorithm; // swap

import basics.help;
import basics.matrix;
import game.lookup;
import graphic.color;
import graphic.graphic;
import graphic.gralib;
import graphic.torbit;
import lix.enums;
import lix.acfunc;

// import editor.graphed;
// import game.lookup;
// import graphic.map;
// import graphic.graphbg;
// import graphic.sound;
// import basics.types;

// DTODOCOMMENT: add the interesting things from the 150+ line comment in
// C++/A4 Lix's lix/lix.h top comment.

import lix.acfunc;

// DTODO: implement these classes
struct GameState { int update; }
struct UpdateArgs { int id; int ud; GameState st; }
class EdGraphic { }
class EffectManager {
    void add_sound        (in int, in Tribe, int, in Sound.Id) { }
    void add_sound_if_trlo(in int, in Tribe, int, in Sound.Id) { }
}
class Tribe { Style style; }
class Map : Torbit {
    this(in int xl, in int yl, in bool tx = false, in bool ty = false) {
        super(xl, yl, tx, ty);
    }
}

class Lixxie : Graphic {

private:

    int  ex;
    int  ey;
    int  dir;
    int  special_x;
    int  special_y;
    int  queue; // builders and platformers can be queued in advance

    Tribe tribe;
    bool  marked;

    int  fling_x;
    int  fling_y;
    bool fling_new;
    bool fling_by_same_tribe;

    int  frame;
    int  updates_since_bomb;
    bool exploder_knockback;

    bool runner;
    bool climber;
    bool floater;

    Lookup.LoNr enc_body;
    Lookup.LoNr enc_foot;

    Style style;
    Ac    ac;

    void draw_at(const int, const int);

    static Torbit        land;
    static Lookup        lookup;
    static Map           ground_map;
    static EffectManager effect;

    static bool any_new_flingers;

public:

    static immutable int distance_safe_fall = 126;
    static immutable int distance_float     =  60;
    static immutable int updates_for_bomb   =  75;

    this(Tribe = null, int = 0, int = 0); // tribe==null ? NOTHING : FALLER
    ~this() { }
    // invariant() -- exists, see below

    deprecated static void initialize_this_gets_called_from_glob_gfx_cpp()
        { assert (false, "DTODO: initialize_this_gets..."); }

    static void    set_static_maps   (Torbit, Lookup, Map);
    static void    set_effect_manager(EffectManager e) { effect = e;    }
    static EffectManager get_ef()                      { return effect; }
    static const Torbit  get_land()                    { return land;   }
    static bool    get_any_new_flingers()    { return any_new_flingers; }

    bool get_mark() const { return marked;  }
    void mark()           { marked = true;  }
    void unmark()         { marked = false; }

    inout(Tribe) get_tribe() inout { return tribe; }
          Style  get_style() const { return style; }

    int  get_ex() const { return ex; }
    int  get_ey() const { return ey; }
    void set_ex(in int);
    void set_ey(in int);

    void move_ahead(   int = 2);
    void move_down (   int = 2);
    void move_up   (in int = 2);

    int  get_dir() const   { return dir; }
    void set_dir(in int i) { dir = (i > 0) ? 1 : (i < 0) ? -1 : dir; }
    void turn()            { dir *= -1; }

    bool get_in_trigger_area(const EdGraphic) const;

    Ac   get_ac() const       { return ac;   }
    void get_ac(in Ac new_ac) { ac = new_ac; }

    bool get_pass_top () const { return ac_func[ac].pass_top;  }
    bool get_leaving  () const { return ac_func[ac].leaving;   }
    bool get_blockable() const { return ac_func[ac].blockable; }

    Sound.Id get_sound_assign() const { return ac_func[ac].sound_assign; }
    Sound.Id get_sound_become() const { return ac_func[ac].sound_become; }

    void evaluate_click(Ac);
    int  get_priority  (Ac, bool);

    int  get_special_x()      { return special_x; }
    int  get_special_y()      { return special_y; }
    int  get_queue()          { return queue;     }
    void set_special_x(int i) { special_x = i;    }
    void set_special_y(int i) { special_y = i;    }
    void set_queue    (int i) { queue     = i;    }

    bool get_fling_new() const { return fling_new; }
    int  get_fling_x()   const { return fling_x;   }
    int  get_fling_y()   const { return fling_y;   }
    void add_fling(in int, in int, in bool = false); // bool = from same tribe
    void reset_fling_new();

    int  get_updates_since_bomb()         { return updates_since_bomb; }
    void inc_updates_since_bomb()         { ++updates_since_bomb;      }
    void set_updates_since_bomb(in int i) { updates_since_bomb = i;    }

    bool get_exploder_knockback() const        { return exploder_knockback; }
    void set_exploder_knockback(bool b = true) { exploder_knockback=b;      }

    bool get_runner () const { return runner;  }
    bool get_climber() const { return climber; }
    bool get_floater() const { return floater; }
    void set_runner ()       { runner  = true; }
    void set_climber()       { climber = true; }
    void set_floater()       { floater = true; }

    static bool get_steel_absolute(in int, in int);
    bool get_steel         (in int = 0, in int = 0);

    // don't call add_land from the skills, use draw_pixel. That amends
    // the x-direction by left-looking lixes by the desired 1 pixel. Kludge:
    // Maybe remove add_land entirely and put the functionality in draw_pixel?
    void add_land          (in int = 0, in int = 0, in AlCol = color.transp);
    void add_land_absolute (in int = 0, in int = 0, in AlCol = color.transp);

    bool is_solid          (in int = 0, in int = 2);
    bool is_solid_single   (in int = 0, in int = 2);
    int  solid_wall_height (in int = 0, in int = 0);
    int  count_solid       (int, int, int, int);
    int  count_steel       (int, int, int, int);

    static void remove_pixel_absolute(in int, in int);
    bool        remove_pixel         (   int, in int);
    bool        remove_rectangle     (int, int, int, int);

    void draw_pixel       (int,      in int,   in AlCol);
    void draw_rectangle   (int, int, int, int, in AlCol);
    void draw_brick       (int, int, int, int);
    void draw_frame_to_map(int, int, int, int, int, int, int, int);

    void play_sound        (in ref UpdateArgs, in Sound.Id);
    void play_sound_if_trlo(in ref UpdateArgs, in Sound.Id);

    int  get_frame() const   { return frame; }
    void set_frame(in int i) { frame = i;    }
    void next_frame(in int = 0);
    // override bool is_last_frame() const; -- exists, see below

    Lookup.LoNr get_body_encounters()   { return enc_body;         }
    Lookup.LoNr get_foot_encounters()   { return enc_foot;         }
    void        set_no_encounters()     { enc_body = enc_foot = 0; }
    void        set_body_encounters(Lookup.LoNr n) { enc_body = n; }
    void        set_foot_encounters(Lookup.LoNr n) { enc_foot = n; }

    void assclk        (in Ac);
    void become        (in Ac);
    void become_default(in Ac);
    void update        (in ref UpdateArgs);

    // override void draw(); -- exists, see below



public:

this(
    Tribe new_tribe,
    int   new_ex,
    int   new_ey
) {
    super(graphic.gralib.get_lix(new_tribe ? new_tribe.style : Style.GARDEN),
          ground_map, even(new_ex) - lix.enums.ex_offset,
                           new_ey  - lix.enums.ey_offset);
    tribe = new_tribe;
    dir   = 1;
    style = tribe ? tribe.style : Style.GARDEN,
    ac    = Ac.NOTHING;
    if (tribe) {
        become(Ac.FALLER);
        frame = 4;
    }
    // important for torus bitmaps: calculate modulo in time
    set_ex(even(new_ex));
    set_ey(     new_ey );
}



invariant()
{
    assert (dir == -1 || dir == 1);
}



static void set_static_maps(Torbit tb, Lookup lo, Map ma)
{
    land = tb;
    lookup = lo;
    ground_map = ma;
}



private int frame_to_x_frame() const { return frame + 2; }
private int ac_to_y_frame   () const { return ac - 1;    }

private XY get_fuse_xy() const
{
    XY ret = countdown.get(frame_to_x_frame(), ac_to_y_frame());
    if (dir < 0) ret.x = graphic.gralib.get_lix(style).get_xl() - ret.x;
    ret.x += get_x();
    ret.y += get_y();
    return ret;
}



void set_ex(in int n) {
    ex = basics.help.even(n);
    set_x(ex - lix.enums.ex_offset);
    if (ground_map.get_torus_x()) ex = positive_mod(ex, land.get_xl());
    immutable XY fuse_xy = get_fuse_xy();
    enc_foot |= lookup.get(ex, ey);
    enc_body |= enc_foot
             |  lookup.get(ex, ey - 4)
             |  lookup.get(fuse_xy.x, fuse_xy.y);
}



void set_ey(in int n) {
    ey = n;
    set_y(ey - lix.enums.ey_offset);
    if (ground_map.get_torus_y()) ey = positive_mod(ey, land.get_yl());
    immutable XY fuse_xy = get_fuse_xy();
    enc_foot |= lookup.get(ex, ey);
    enc_body |= enc_foot
             |  lookup.get(ex, ey - 4)
             |  lookup.get(fuse_xy.x, fuse_xy.y);
}



void move_ahead(int plus_x)
{
    plus_x = even(plus_x);
    plus_x *= dir;
    // move in little steps, to check for lookupmap encounters on the way
    for ( ; plus_x > 0; plus_x -= 2) set_ex(ex + 2);
    for ( ; plus_x < 0; plus_x += 2) set_ex(ex - 2);
}



void move_down(int plus_y)
{
    for ( ; plus_y > 0; --plus_y) set_ey(ey + 1);
    for ( ; plus_y < 0; ++plus_y) set_ey(ey - 1);
}



void move_up(in int minus_y)
{
    move_down(-minus_y);
}



bool get_in_trigger_area(const EdGraphic gr) const
{
    assert (false, "DTODO: implement get_in_trigger_area");
    /*
    const Object& ob = *gr.get_object();
    return ground_map->get_point_in_rectangle(
        get_ex(), get_ey(),
        gr.get_x() + ob.get_trigger_x(),
        gr.get_y() + ob.get_trigger_y(),
        ob.trigger_xl, ob.trigger_yl);
    */
}



void add_fling(in int px, in int py, in bool same_tribe)
{
    if (fling_by_same_tribe && same_tribe) return;

    any_new_flingers    = true;
    fling_by_same_tribe = (fling_by_same_tribe || same_tribe);
    fling_new = true;
    fling_x   += px;
    fling_y   += py;
}



void reset_fling_new()
{
    any_new_flingers    = false;
    fling_new           = false;
    fling_by_same_tribe = false;
    fling_x             = 0;
    fling_y             = 0;
}



void evaluate_click(Ac ac)         { assert (false, "DTODO: evaluate_click not impl");      }
int  get_priority  (Ac ac, bool b) { assert (false, "DTODO: get_priority not implemented"); }



bool get_steel(in int px, in int py)
{
    return lookup.get_steel(ex + px * dir, ey + py);
}



static bool get_steel_absolute(in int x, in int y)
{
    return lookup.get_steel(x, y);
}



void add_land(in int px, in int py, const AlCol col)
{
    add_land_absolute(ex + px * dir, ey + py, col);
}



// this one could be static
void add_land_absolute(in int x = 0, in int y = 0, in AlCol col = color.transp)
{
    // DTODOVRAM: land.set_pixel should be very slow, think hard
    land.set_pixel(x, y, col);
    lookup.add    (x, y, Lookup.bit_terrain);
}



bool is_solid(in int px, in int py)
{
    return lookup.get_solid_even(ex + px * dir, ey + py);
}



bool is_solid_single(in int px, in int py)
{
    return lookup.get_solid(ex + px * dir, ey + py);
}



int solid_wall_height(in int px, in int py)
{
    int solid = 0;
    for (int i = 1; i > -12; --i) {
        if (is_solid(px, py + i)) ++solid;
        else break;
    }
    return solid;
}



int count_solid(int x1, int y1, int x2, int y2)
{
    if (x2 < x1) swap(x1, x2);
    if (y2 < y1) swap(y1, y2);
    int ret = 0;
    for (int ix = basics.help.even(x1); ix <= even(x2); ix += 2) {
        for (int iy = y1; iy <= y2; ++iy) {
            if (is_solid(ix, iy)) ++ret;
        }
    }
    return ret;
}



int count_steel(int x1, int y1, int x2, int y2)
{
    if (x2 < x1) swap(x1, x2);
    if (y2 < y1) swap(y1, y2);
    int ret = 0;
    for (int ix = even(x1); ix <= even(x2); ix += 2) {
        for (int iy = y1; iy <= y2; ++iy) {
            if (get_steel(ix, iy)) ++ret;
        }
    }
    return ret;
}



// ############################################################################
// ############# finished with the removal functions, now the drawing functions
// ############################################################################



bool remove_pixel(int px, in int py)
{
    // this amendmend is only in draw_pixel() and remove_pixel()
    if (dir < 0) --px;

    // test whether the landscape can be dug
    if (! get_steel(px, py) && is_solid(px, py)) {
        lookup.rm     (ex + px * dir, ey + py, Lookup.bit_terrain);
        land.set_pixel(ex + px * dir, ey + py, color.transp);
        return false;
    }
    // Stahl?
    else if (get_steel(px, py)) return true;
    else return false;
}



void remove_pixel_absolute(in int x, in int y)
{
    if (! get_steel_absolute(x, y) && lookup.get_solid(x, y)) {
        lookup.rm(x, y, Lookup.bit_terrain);
        land.set_pixel(x, y, color.transp);
    }
}



bool remove_rectangle(int x1, int y1, int x2, int y2)
{
    if (x2 < x1) swap(x1, x2);
    if (y2 < y1) swap(y1, y2);
    bool ret = false;
    for (int ix = x1; ix <= x2; ++ix) {
        for (int iy = y1; iy <= y2; ++iy) {
            // return true if at least one pixel has been steel
            if (remove_pixel(ix, iy)) ret = true;
        }
    }
    return ret;
}



// like remove_pixel
void draw_pixel(int px, in int py, in AlCol col)
{
    // this amendmend is only in draw_pixel() and remove_pixel()
    if (dir < 0) --px;

    if (! is_solid_single(px, py)) add_land(px, py, col);
}



void draw_rectangle(int x1, int y1, int x2, int y2, in AlCol col)
{
    if (x2 < x1) swap(x1, x2);
    if (y2 < y1) swap(y1, y2);
    for (int ix = x1; ix <= x2; ++ix) {
        for (int iy = y1; iy <= y2; ++iy) {
            draw_pixel(ix, iy, col);
        }
    }
}



void draw_brick(int x1, int y1, int x2, int y2)
{
    assert (false, "DTODO: implement lixxie.draw_brick. Cache the colors!");
    /*
    const int col_l = get_cutbit()->get_pixel(19, LixEn::BUILDER - 1, 0, 0);
    const int col_m = get_cutbit()->get_pixel(20, LixEn::BUILDER - 1, 0, 0);
    const int col_d = get_cutbit()->get_pixel(21, LixEn::BUILDER - 1, 0, 0);

    draw_rectangle(x1 + (dir<0), y1, x2 - (dir>0), y1, col_l);
    draw_rectangle(x1 + (dir>0), y2, x2 - (dir<0), y2, col_d);
    if (dir > 0) {
        draw_pixel(x2, y1, col_m);
        draw_pixel(x1, y2, col_m);
    }
    else {
        draw_pixel(x1, y1, col_m);
        draw_pixel(x2, y2, col_m);
    }
    */
}



// Draws the the rectangle specified by xs, ys, ws, hs of the
// specified animation frame onto the level map at position (xd, yd),
// as diggable terrain. (xd, yd) specifies the top left of the destination
// rectangle relative to the lix's position
void draw_frame_to_map
(
    int frame, int anim,
    int xs, int ys, int ws, int hs,
    int xd, int yd
) {
    assert (false, "DTODO: implement draw_frame_to_map (as terrain => speed!");
    /*
    for (int y = 0; y < hs; ++y) {
        for (int x = 0; x < ws; ++x) {
            const AlCol col = get_cutbit().get_pixel(frame, anim, xs+x, ys+y);
            if (col != color.transp && ! get_steel(xd + x, yd + y)) {
                add_land(xd + x, yd + y, col);
            }
        }
    }
    */
}



void play_sound(in ref UpdateArgs ua, in Sound.Id sound_id)
{
    assert (effect);
    effect.add_sound(ua.st.update, tribe, ua.id, sound_id);
}



void play_sound_if_trlo(in ref UpdateArgs ua, in Sound.Id sound_id)
{
    assert (effect);
    effect.add_sound_if_trlo(ua.st.update, tribe, ua.id, sound_id);
}



override bool is_last_frame() const
{
    // the cutbit does this for us. Lixxie.frame != Graphic.x_frame,
    // so we use Lixxie's private conversion functions
    return ! get_cutbit().get_frame_exists(frame_to_x_frame() + 1,
                                           ac_to_y_frame());
}



void next_frame(in int loop)
{
    // Kludge: do we want frame + 3 here or frame + 1? Examine this's callers
    if (is_last_frame() || frame + 3 == loop) frame = 0;
    else frame++;
}



void assclk        (in Ac) { assert (false, "DTODO: implement assclk!"); }
void become        (in Ac) { assert (false, "DTODO: implement become!"); }
void become_default(in Ac) { assert (false, "DTODO: impls become_default!"); }
void update        (in ref UpdateArgs) {
    assert (false, "DTODO: implement lixxie.update()!");
}

}
// end class Lixxie