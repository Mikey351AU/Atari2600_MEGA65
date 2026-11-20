----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Configuration data for the Shell
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity config is
port (
   clk_i       : in std_logic;

   -- bits 27 .. 12:    select configuration data block; called "Selector" hereafter
   -- bits 11 downto 0: address the up to 4k the configuration data
   address_i   : in std_logic_vector(27 downto 0);

   -- config data
   data_o      : out std_logic_vector(15 downto 0)
);
end entity config;

architecture beh of config is

--------------------------------------------------------------------------------------------------------------------
-- String and character constants (specific for the Anikki-16x16 font)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant CHR_LINE_1  : character := character'val(196);
constant CHR_LINE_5  : string := CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1;
constant CHR_LINE_10 : string := CHR_LINE_5 & CHR_LINE_5;
constant CHR_LINE_50 : string := CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10;

--------------------------------------------------------------------------------------------------------------------
-- Welcome and Help Screens (Selectors 0x1000 .. 0x1FFF)
--------------------------------------------------------------------------------------------------------------------

-- define the amount of WHS array elements: between 1 and 16
constant WHS_RECORDS   : natural := 2;

-- define the maximum amount of pages per WHS array element: between 1 and 256
-- (this is necessary because Vivado does not support unconstrained arrays in a record)
constant WHS_MAX_PAGES : natural := 2;

 -- !!! DO NOT TOUCH !!!
constant SEL_WHS           : std_logic_vector(15 downto 0) := x"1000";
type WHS_INDEX_TYPE is array (0 to WHS_MAX_PAGES - 1) of natural;
type WHS_RECORD_TYPE is record
   page_count  : natural;
   page_start  : WHS_INDEX_TYPE;
   page_length : WHS_INDEX_TYPE;
end record;
type WHS_RECORD_ARRAY_TYPE is array (0 to WHS_RECORDS - 1) of WHS_RECORD_TYPE;

-- START YOUR CONFIGURATION BELOW THIS LINE

-- IMPORTANT: The OSM resolution is 640 x 384 pixels (VGA_DX/VGA_DY in globals.vhd), i.e. 40 x 24
-- characters. Minus the frame, every line can have at most 38 characters and every screen at most
-- 22 lines.

constant SCR_WELCOME : string :=

   " Atari 2600 for MEGA65 Version 0.1\n\n" &

   " MiSTer core: A2601 by Retromaster,\n" &
   " MiSTer port by Sorgelig and others\n\n" &

   -- We are not insisting. But it would be nice if you gave us credit for MiSTer2MEGA65 by leaving these lines in
   " Powered by MiSTer2MEGA65\n" &
   " by sy2002 and MJoergen\n\n" &

   " Key              Function\n" &
   " " & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_5 & "\n" &
   " Help             Menu and cartridges\n" &
   " Cursor keys      Joystick 1\n" &
   " Space            Fire (joystick 1)\n" &
   " F1               Game Select switch\n" &
   " F3               Game Reset switch\n\n" &

   " Joysticks or paddles: ports 1 and 2\n\n" &

   " Press Space to continue.\n";

constant HELP_1 : string :=

   "\n Atari 2600 for MEGA65 Version 0.1\n\n" &

   " Load a cartridge (.a26, .bin) with\n" &
   " 'Cartridge' in the menu (max. 64 KB).\n\n" &

   " The bank switching scheme is\n" &
   " detected from the cartridge (like the\n" &
   " Stella emulator). If a game does not\n" &
   " work, set it in 'Cart type', e.g.\n" &
   " E0 Parker Bros., FE Activision 8K,\n" &
   " 3F Tigervision.\n\n" &

   " Superchip RAM is detected for 8K,\n" &
   " 16K and 32K carts (Superchip: Auto).\n\n" &

   " Changes need a reset of the core.\n\n" &

   " Cursor right: next page    (1 of 2)\n" &
   " Space: close help";

constant HELP_2 : string :=

   "\n Controls\n\n" &

   " Joysticks: ports 1 and 2. Cursor\n" &
   " keys and Space work as joystick 1.\n\n" &

   " Paddles: select 'Controls: Paddles'.\n" &
   " Port 1 = paddles 1 and 2, port 2 =\n" &
   " paddles 3 and 4. Press each paddle\n" &
   " button once to activate it (as on\n" &
   " MiSTer). 'Invert paddles' turns the\n" &
   " direction.\n\n" &

   " Console switches: F1 = Game Select,\n" &
   " F3 = Game Reset. Difficulty and\n" &
   " B&W/colour are in the menu.\n\n" &

   " Cursor left: previous page (2 of 2)\n" &
   " Space: close help";

-- Concatenate all your Welcome and Help screens into one large string, so that during synthesis one large string ROM can be build.
constant WHS_DATA : string := SCR_WELCOME & HELP_1 & HELP_2;

constant SCR_WELCOME_START : natural := 0;
constant HELP_1_START      : natural := SCR_WELCOME'length;
constant HELP_2_START      : natural := HELP_1_START + HELP_1'length;

constant WHS : WHS_RECORD_ARRAY_TYPE := (
   --- Welcome Screen
   (page_count    => 1,
    page_start    => (SCR_WELCOME_START,  0),
    page_length   => (SCR_WELCOME'length, 0)),

   --- Help pages
   (page_count    => 2,
    page_start    => (HELP_1_START,  HELP_2_START),
    page_length   => (HELP_1'length, HELP_2'length))
);

--------------------------------------------------------------------------------------------------------------------
-- Set start folder for file browser and specify config file for menu persistence (Selectors 0x0100 and 0x0101)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant SEL_DIR_START     : std_logic_vector(15 downto 0) := x"0100";
constant SEL_CFG_FILE      : std_logic_vector(15 downto 0) := x"0101";

-- START YOUR CONFIGURATION BELOW THIS LINE

constant DIR_START         : string := "/atari2600";
constant CFG_FILE          : string := "/atari2600/a26cfg";

--------------------------------------------------------------------------------------------------------------------
-- General configuration settings: Reset, Pause, OSD behavior, Ascal, etc. (Selector 0x0110)
--------------------------------------------------------------------------------------------------------------------

constant SEL_GENERAL       : std_logic_vector(15 downto 0) := x"0110";  -- !!! DO NOT TOUCH !!!

-- START YOUR CONFIGURATION BELOW THIS LINE

constant RESET_COUNTER     : natural := 100;

-- put the core in PAUSE state if any OSD opens
-- Atari 2600: must be false. Pausing halts the CPU (RDY), and on the 2600 the game software itself
-- generates VSYNC every frame, so a paused core outputs a picture without vertical sync (garbage
-- behind the menu, game graphics gone while the menu is open). MiSTer does not pause this core
-- when its OSD opens either. The game keeps running behind the menu; inputs are disconnected.
constant OPTM_PAUSE        : boolean := false;

constant WELCOME_ACTIVE    : boolean := true;
constant WELCOME_AT_RESET  : boolean := false;

constant KEYBOARD_AT_RESET : boolean := false;
constant JOY_1_AT_RESET    : boolean := false;
constant JOY_2_AT_RESET    : boolean := false;

constant KEYBOARD_AT_OSD   : boolean := false;
constant JOY_1_AT_OSD      : boolean := false;
constant JOY_2_AT_OSD      : boolean := false;

constant ASCAL_USAGE       : natural := 2;
constant ASCAL_MODE        : natural := 0;

constant SAVE_SETTINGS     : boolean := true;

constant VD_ANTI_THRASHING_DELAY : natural := 2000;
constant VD_ITERATION_SIZE       : natural := 100;

--------------------------------------------------------------------------------------------------------------------
-- Name and version of the core  (Selector 0x0200)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant SEL_CORENAME      : std_logic_vector(15 downto 0) := x"0200";

-- START YOUR CONFIGURATION BELOW THIS LINE

constant CORENAME          : string := "ATARI 2600 FOR MEGA65 V0.1";

--------------------------------------------------------------------------------------------------------------------
-- "Help" menu / Options menu  (Selectors 0x0300 .. 0x0312): DO NOT TOUCH
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!! Selectors for accessing the menu configuration data
constant SEL_OPTM_ITEMS       : std_logic_vector(15 downto 0) := x"0300";
constant SEL_OPTM_GROUPS      : std_logic_vector(15 downto 0) := x"0301";
constant SEL_OPTM_STDSEL      : std_logic_vector(15 downto 0) := x"0302";
constant SEL_OPTM_LINES       : std_logic_vector(15 downto 0) := x"0303";
constant SEL_OPTM_START       : std_logic_vector(15 downto 0) := x"0304";
constant SEL_OPTM_ICOUNT      : std_logic_vector(15 downto 0) := x"0305";
constant SEL_OPTM_MOUNT_DRV   : std_logic_vector(15 downto 0) := x"0306";
constant SEL_OPTM_SINGLESEL   : std_logic_vector(15 downto 0) := x"0307";
constant SEL_OPTM_MOUNT_STR   : std_logic_vector(15 downto 0) := x"0308";
constant SEL_OPTM_DIMENSIONS  : std_logic_vector(15 downto 0) := x"0309";
constant SEL_OPTM_SAVING_STR  : std_logic_vector(15 downto 0) := x"030A";
constant SEL_OPTM_HELP        : std_logic_vector(15 downto 0) := x"0310";
constant SEL_OPTM_CRTROM      : std_logic_vector(15 downto 0) := x"0311";
constant SEL_OPTM_CRTROM_STR  : std_logic_vector(15 downto 0) := x"0312";

-- !!! DO NOT TOUCH !!! Configuration constants for OPTM_GROUPS (shell.asm and menu.asm expect them to be like this)
constant OPTM_G_TEXT       : integer := 16#00000#;         -- text that cannot be selected
constant OPTM_G_CLOSE      : integer := 16#000FF#;        -- menu items that closes menu
constant OPTM_G_STDSEL     : integer := 16#00100#;        -- item within a group that is selected by default
constant OPTM_G_LINE       : integer := 16#00200#;        -- draw a line at this position
constant OPTM_G_START      : integer := 16#00400#;        -- selector / cursor position after startup (only use once!)
                                                          -- 16#00800# is used in OPTM_G_MOUNT_DRV (OPTM_G_SINGLESEL)
constant OPTM_G_HEADLINE   : integer := 16#01000#;        -- like OPTM_G_TEXT but will be shown in a brigher color
                                                          -- 16#02000# is used in OPTM_G_HELP (plus OPTM_G_SINGLESEL)
                                                          -- 16#04000# is used in OPTM_G_SUBMENU
constant OPTM_G_SINGLESEL  : integer := 16#08000#;        -- single select item
constant OPTM_G_MOUNT_DRV  : integer := 16#08800#;        -- line item means: mount drive; first occurance = drive 0, second = drive 1, ...
constant OPTM_G_HELP       : integer := 16#0A000#;        -- line item means: help screen; first occurance = WHS(1), second = WHS(2), ...
constant OPTM_G_SUBMENU    : integer := 16#0C000#;        -- starts/ends a section that is treated as submenu
constant OPTM_G_LOAD_ROM   : integer := 16#18000#;        -- line item means: load ROM; first occurance = rom 0, second = rom 1, ...

constant OPTM_GTC          : natural := 17;                -- Amount of significant bits in OPTM_G_* constants

--------------------------------------------------------------------------------------------------------------------
-- "Help" menu / Options menu: START YOUR CONFIGURATION BELOW THIS LINE
--------------------------------------------------------------------------------------------------------------------

constant OPTM_S_MOUNT      : string := "<Mount>";
constant OPTM_S_CRTROM     : string := "<Load>";            -- no cartridge loaded, yet
constant OPTM_S_SAVING     : string := "<Saving>";

-- IMPORTANT: The menu item positions (0-based line numbers) are used as C_MENU_* constants in mega65.vhd.
--            If you change this menu, update mega65.vhd accordingly.
constant OPTM_SIZE         : natural := 75;  -- amount of items including empty lines:
                                             -- needs to be equal to the number of lines in OPTM_ITEMS and amount of items in OPTM_GROUPS
                                             -- IMPORTANT: If SAVE_SETTINGS is true and OPTM_SIZE changes: Make sure to re-generate and
                                             -- and re-distribute the config file. You can make a new one using M2M/tools/make_config.sh

-- OSM is 40 x 24 characters: OPTM_DX <= 38, OPTM_DY <= 22.
-- OPTM_DY has to fit the main menu (17 lines) and the largest submenu ("Cart type", 19 lines).
constant OPTM_DX           : natural := 34;
constant OPTM_DY           : natural := 19;

constant OPTM_ITEMS        : string :=

   " Atari 2600\n"              &    --  0
   "\n"                         &    --  1
   " Cartridge: %s\n"           &    --  2  load cartridge

   " Cart type: %s\n"           &    --  3  cartridge type submenu
   " Cartridge type\n"          &    --  4
   "\n"                         &    --  5
   " Auto (detect)\n"           &    --  6
   " F8  8K Atari\n"            &    --  7
   " F6  16K Atari\n"           &    --  8
   " F4  32K Atari\n"           &    --  9
   " FE  8K Activision\n"       &    -- 10
   " E0  8K Parker Bros\n"      &    -- 11
   " 3F  Tigervision\n"         &    -- 12
   " FA  12K CBS RAM Plus\n"    &    -- 13
   " CV  Commavid\n"            &    -- 14
   " UA  UA Limited\n"          &    -- 15
   " E7  16K M-Network\n"       &    -- 16
   " F0  64K Dynacom\n"         &    -- 17
   " P2  Pitfall II (DPC)\n"    &    -- 18
   " 32  32-in-1\n"             &    -- 19
   "\n"                         &    -- 20
   " Back\n"                    &    -- 21

   " Superchip: %s\n"           &    -- 22 superchip submenu
   " Superchip RAM\n"           &    -- 23
   "\n"                         &    -- 24
   " Auto\n"                    &    -- 25
   " Off\n"                     &    -- 26
   " On\n"                      &    -- 27
   "\n"                         &    -- 28
   " Back\n"                    &    -- 29

   "\n"                         &    -- 30
   " P1 difficulty A\n"         &    -- 31
   " P2 difficulty A\n"         &    -- 32
   " Black & white\n"           &    -- 33
   "\n"                         &    -- 34

   " Controls: %s\n"            &    -- 35 controls submenu
   " Controls\n"                &    -- 36
   "\n"                         &    -- 37
   " Joysticks\n"               &    -- 38
   " Paddles\n"                 &    -- 39
   "\n"                         &    -- 40
   " Invert paddles\n"          &    -- 41
   " Swap joysticks\n"          &    -- 42
   "\n"                         &    -- 43
   " Back\n"                    &    -- 44

   " Video and audio\n"         &    -- 45 video & audio submenu
   " Video and audio\n"         &    -- 46
   "\n"                         &    -- 47
   " NTSC colors\n"             &    -- 48
   " PAL colors\n"              &    -- 49
   "\n"                         &    -- 50
   " Original VBlank\n"         &    -- 51
   " De-comb\n"                 &    -- 52
   " Stereo audio\n"            &    -- 53
   " Audio improvements\n"      &    -- 54
   " HDMI: CRT emulation\n"     &    -- 55
   " HDMI: Zoom-in\n"           &    -- 56
   "\n"                         &    -- 57
   " Back\n"                    &    -- 58

   " HDMI: %s\n"                &    -- 59 HDMI submenu
   " HDMI mode\n"               &    -- 60
   "\n"                         &    -- 61
   " 720p 50 Hz 16:9\n"         &    -- 62
   " 720p 60 Hz 16:9\n"         &    -- 63
   " 576p 50 Hz 4:3\n"          &    -- 64
   " 576p 50 Hz 5:4\n"          &    -- 65
   " 640x480 60 Hz\n"           &    -- 66
   " 720x480 59.94 Hz\n"        &    -- 67
   " 800x600 60 Hz\n"           &    -- 68
   "\n"                         &    -- 69
   " Back\n"                    &    -- 70

   "\n"                         &    -- 71
   " About & Help\n"            &    -- 72
   "\n"                         &    -- 73
   " Close Menu\n";                  -- 74

-- Group ids: must start with 1 and be monotonic increasing
constant OPTM_G_Cart       : integer := 1;
constant OPTM_G_CartType   : integer := 2;
constant OPTM_G_SC         : integer := 3;
constant OPTM_G_Dif1       : integer := 4;
constant OPTM_G_Dif2       : integer := 5;
constant OPTM_G_BW         : integer := 6;
constant OPTM_G_Ctrl       : integer := 7;
constant OPTM_G_InvPad     : integer := 8;
constant OPTM_G_Swap       : integer := 9;
constant OPTM_G_Pal        : integer := 10;
constant OPTM_G_VblOrig    : integer := 11;
constant OPTM_G_Decomb     : integer := 12;
constant OPTM_G_Stereo     : integer := 13;
constant OPTM_G_Audio      : integer := 14;
constant OPTM_G_CRT        : integer := 15;
constant OPTM_G_Zoom       : integer := 16;
constant OPTM_G_HDMI       : integer := 17;
constant OPTM_G_About      : integer := 18;

-- !!! DO NOT TOUCH !!!
type OPTM_GTYPE is array (0 to OPTM_SIZE - 1) of integer range 0 to 2**OPTM_GTC- 1;

constant OPTM_GROUPS       : OPTM_GTYPE := ( OPTM_G_TEXT + OPTM_G_HEADLINE,            --  0 Headline
                                             OPTM_G_LINE,                              --  1 Line
                                             OPTM_G_Cart + OPTM_G_LOAD_ROM + OPTM_G_START, -- 2 Load cartridge; cursor start

                                             OPTM_G_SUBMENU,                           --  3 Cart type submenu START
                                             OPTM_G_TEXT + OPTM_G_HEADLINE,            --  4
                                             OPTM_G_LINE,                              --  5
                                             OPTM_G_CartType + OPTM_G_STDSEL,          --  6 Auto (default)
                                             OPTM_G_CartType,                          --  7 F8
                                             OPTM_G_CartType,                          --  8 F6
                                             OPTM_G_CartType,                          --  9 F4
                                             OPTM_G_CartType,                          -- 10 FE
                                             OPTM_G_CartType,                          -- 11 E0
                                             OPTM_G_CartType,                          -- 12 3F
                                             OPTM_G_CartType,                          -- 13 FA
                                             OPTM_G_CartType,                          -- 14 CV
                                             OPTM_G_CartType,                          -- 15 UA
                                             OPTM_G_CartType,                          -- 16 E7
                                             OPTM_G_CartType,                          -- 17 F0
                                             OPTM_G_CartType,                          -- 18 P2
                                             OPTM_G_CartType,                          -- 19 32
                                             OPTM_G_LINE,                              -- 20
                                             OPTM_G_CLOSE + OPTM_G_SUBMENU,            -- 21 Back / END

                                             OPTM_G_SUBMENU,                           -- 22 Superchip submenu START
                                             OPTM_G_TEXT + OPTM_G_HEADLINE,            -- 23
                                             OPTM_G_LINE,                              -- 24
                                             OPTM_G_SC + OPTM_G_STDSEL,                -- 25 Auto (default)
                                             OPTM_G_SC,                                -- 26 Off
                                             OPTM_G_SC,                                -- 27 On
                                             OPTM_G_LINE,                              -- 28
                                             OPTM_G_CLOSE + OPTM_G_SUBMENU,            -- 29 Back / END

                                             OPTM_G_LINE,                              -- 30
                                             OPTM_G_Dif1 + OPTM_G_SINGLESEL,           -- 31 P1 difficulty A (off = B)
                                             OPTM_G_Dif2 + OPTM_G_SINGLESEL,           -- 32 P2 difficulty A (off = B)
                                             OPTM_G_BW   + OPTM_G_SINGLESEL,           -- 33 Black & white
                                             OPTM_G_LINE,                              -- 34

                                             OPTM_G_SUBMENU,                           -- 35 Controls submenu START
                                             OPTM_G_TEXT + OPTM_G_HEADLINE,            -- 36
                                             OPTM_G_LINE,                              -- 37
                                             OPTM_G_Ctrl + OPTM_G_STDSEL,              -- 38 Joysticks (default)
                                             OPTM_G_Ctrl,                              -- 39 Paddles
                                             OPTM_G_LINE,                              -- 40
                                             OPTM_G_InvPad + OPTM_G_SINGLESEL,         -- 41 Invert paddles
                                             OPTM_G_Swap   + OPTM_G_SINGLESEL,         -- 42 Swap joysticks
                                             OPTM_G_LINE,                              -- 43
                                             OPTM_G_CLOSE + OPTM_G_SUBMENU,            -- 44 Back / END

                                             OPTM_G_SUBMENU,                           -- 45 Video and audio submenu START
                                             OPTM_G_TEXT + OPTM_G_HEADLINE,            -- 46
                                             OPTM_G_LINE,                              -- 47
                                             OPTM_G_Pal + OPTM_G_STDSEL,               -- 48 NTSC colors (default)
                                             OPTM_G_Pal,                               -- 49 PAL colors
                                             OPTM_G_LINE,                              -- 50
                                             OPTM_G_VblOrig + OPTM_G_SINGLESEL,        -- 51 Original VBlank
                                             OPTM_G_Decomb  + OPTM_G_SINGLESEL,        -- 52 De-comb
                                             OPTM_G_Stereo  + OPTM_G_SINGLESEL,        -- 53 Stereo audio
                                             OPTM_G_Audio   + OPTM_G_SINGLESEL,        -- 54 Audio improvements
                                             OPTM_G_CRT     + OPTM_G_SINGLESEL,        -- 55 HDMI: CRT emulation
                                             OPTM_G_Zoom    + OPTM_G_SINGLESEL,        -- 56 HDMI: Zoom-in
                                             OPTM_G_LINE,                              -- 57
                                             OPTM_G_CLOSE + OPTM_G_SUBMENU,            -- 58 Back / END

                                             OPTM_G_SUBMENU,                           -- 59 HDMI submenu START
                                             OPTM_G_TEXT + OPTM_G_HEADLINE,            -- 60
                                             OPTM_G_LINE,                              -- 61
                                             OPTM_G_HDMI,                              -- 62 720p 50 Hz 16:9
                                             OPTM_G_HDMI + OPTM_G_STDSEL,              -- 63 720p 60 Hz 16:9 (default: NTSC is 60 Hz)
                                             OPTM_G_HDMI,                              -- 64 576p 50 Hz 4:3
                                             OPTM_G_HDMI,                              -- 65 576p 50 Hz 5:4
                                             OPTM_G_HDMI,                              -- 66 640x480 60 Hz
                                             OPTM_G_HDMI,                              -- 67 720x480 59.94 Hz
                                             OPTM_G_HDMI,                              -- 68 800x600 60 Hz
                                             OPTM_G_LINE,                              -- 69
                                             OPTM_G_CLOSE + OPTM_G_SUBMENU,            -- 70 Back / END

                                             OPTM_G_LINE,                              -- 71
                                             OPTM_G_About + OPTM_G_HELP,               -- 72 About & Help -> WHS(1)
                                             OPTM_G_LINE,                              -- 73
                                             OPTM_G_CLOSE                              -- 74 Close Menu
                                           );

--------------------------------------------------------------------------------------------------------------------
-- !!! CAUTION: M2M FRAMEWORK CODE !!! DO NOT TOUCH ANYTHING BELOW THIS LINE !!!
--------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------
-- Address Decoding
--------------------------------------------------------------------------------------------------------------------

begin

addr_decode : process(clk_i)
   -- return ASCII value of given string at the position defined by index (zero-based)
   pure function str2data(str : string; index : integer) return std_logic_vector is
   variable strpos : integer;
   begin
      strpos := index + 1;
      if strpos <= str'length then
         return std_logic_vector(to_unsigned(character'pos(str(strpos)), 16));
      else
         return X"0000"; -- zero terminated strings
      end if;
   end function str2data;

   -- return the dimensions of the Options menu
   pure function getDXDY(dx, dy, index: natural) return std_logic_vector is
   begin
      case index is
         when 0 => return std_logic_vector(to_unsigned(dx + 2, 16));
         when 1 => return std_logic_vector(to_unsigned(dy + 2, 16));
         when others => return X"0000";
      end case;
   end function getDXDY;

   -- convert bool to std_logic_vector
   pure function bool2slv(b: boolean) return std_logic_vector is
   begin
      if b then
         return x"0001";
      else
         return x"0000";
      end if;
   end function bool2slv;

   -- return the General Configuration settings
   function getGenConf(index: natural) return std_logic_vector is
   begin
      case index is
         when 1      => return std_logic_vector(to_unsigned(RESET_COUNTER, 16));
         when 2      => return bool2slv(OPTM_PAUSE);
         when 3      => return bool2slv(WELCOME_ACTIVE);
         when 4      => return bool2slv(WELCOME_AT_RESET);
         when 5      => return bool2slv(KEYBOARD_AT_RESET);
         when 6      => return bool2slv(JOY_1_AT_RESET);
         when 7      => return bool2slv(JOY_2_AT_RESET);
         when 8      => return bool2slv(KEYBOARD_AT_OSD);
         when 9      => return bool2slv(JOY_1_AT_OSD);
         when 10     => return bool2slv(JOY_2_AT_OSD);
         when 11     => return std_logic_vector(to_unsigned(ASCAL_USAGE, 16));
         when 12     => return std_logic_vector(to_unsigned(ASCAL_MODE, 16));
         when 13     => return std_logic_vector(to_unsigned(VD_ANTI_THRASHING_DELAY, 16));
         when 14     => return std_logic_vector(to_unsigned(VD_ITERATION_SIZE, 16));
         when 15     => return bool2slv(SAVE_SETTINGS);
         when others => return x"0000";
      end case;
   end function getGenConf;

   variable index           : integer;
   variable whs_page_index  : integer;
   variable whs_array_index : integer;

begin

   if falling_edge(clk_i) then

      index := to_integer(unsigned(address_i(11 downto 0)));
      whs_page_index  := to_integer(unsigned(address_i(19 downto 12)));
      whs_array_index := to_integer(unsigned(address_i(23 downto 20)));

      data_o <= x"EEEE";

      -----------------------------------------------------------------------------------
      -- Welcome & Help System: upper 4 bits of address equal SEL_WHS' upper 4 bits
      -----------------------------------------------------------------------------------

      if address_i(27 downto 24) = SEL_WHS(15 downto 12) then

         if  whs_array_index < WHS_RECORDS then
            if index = 4095 then
               data_o <= std_logic_vector(to_unsigned(WHS(whs_array_index).page_count, 16));
            else
               if index < WHS(whs_array_index).page_length(whs_page_index) then
                  data_o <= str2data(WHS_DATA, WHS(whs_array_index).page_start(whs_page_index) + index);
               else
                  data_o <= (others => '0'); -- zero-terminated strings
               end if;
            end if;
         end if;

      -----------------------------------------------------------------------------------
      -- All other selectors, which are 16-bit values
      -----------------------------------------------------------------------------------

      else

         case address_i(27 downto 12) is
            when SEL_GENERAL           => data_o <= getGenConf(index);
            when SEL_DIR_START         => data_o <= str2data(DIR_START, index);
            when SEL_CFG_FILE          => data_o <= str2data(CFG_FILE, index);
            when SEL_CORENAME          => data_o <= str2data(CORENAME, index);
            when SEL_OPTM_ITEMS        => data_o <= str2data(OPTM_ITEMS, index);
            when SEL_OPTM_MOUNT_STR    => data_o <= str2data(OPTM_S_MOUNT, index);
            when SEL_OPTM_CRTROM_STR   => data_o <= str2data(OPTM_S_CRTROM, index);
            when SEL_OPTM_SAVING_STR   => data_o <= str2data(OPTM_S_SAVING, index);
            when SEL_OPTM_GROUPS       => data_o <= std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(15)) &
                                                    std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(14)) & "0" &
                                                    std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(12)) & "0000" &
                                                    std_logic_vector(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(7 downto 0));
            when SEL_OPTM_STDSEL       => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(8));
            when SEL_OPTM_LINES        => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(9));
            when SEL_OPTM_START        => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(10));
            when SEL_OPTM_MOUNT_DRV    => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(11));
            when SEL_OPTM_HELP         => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(13));
            when SEL_OPTM_SINGLESEL    => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(15));
            when SEL_OPTM_CRTROM       => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(16));
            when SEL_OPTM_ICOUNT       => data_o <= x"00" & std_logic_vector(to_unsigned(OPTM_SIZE, 8));
            when SEL_OPTM_DIMENSIONS   => data_o <= getDXDY(OPTM_DX, OPTM_DY, index);

            when others                => null;
         end case;
      end if;
   end if;
end process;

end architecture beh;

