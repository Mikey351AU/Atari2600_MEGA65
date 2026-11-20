----------------------------------------------------------------------------------
-- Atari 2600 for MEGA65
--
-- MEGA65 main file that contains the whole machine (based on the MiSTer2MEGA65 framework)
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.globals.all;
use work.types_pkg.all;
use work.video_modes_pkg.all;

library xpm;
use xpm.vcomponents.all;

entity MEGA65_Core is
generic (
   G_BOARD : string                                         -- Which platform are we running on.
);
port (
   --------------------------------------------------------------------------------------------------------
   -- QNICE Clock Domain
   --------------------------------------------------------------------------------------------------------

   -- Get QNICE clock from the framework: for the vdrives as well as for RAMs and ROMs
   qnice_clk_i             : in  std_logic;
   qnice_rst_i             : in  std_logic;

   -- Video and audio mode control
   qnice_dvi_o             : out std_logic;              -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_video_mode_o      : out video_mode_type;        -- Defined in video_modes_pkg.vhd
   qnice_osm_cfg_scaling_o : out std_logic_vector(8 downto 0);
   qnice_scandoubler_o     : out std_logic;              -- 0 = no scandoubler, 1 = scandoubler
   qnice_audio_mute_o      : out std_logic;
   qnice_audio_filter_o    : out std_logic;
   qnice_zoom_crop_o       : out std_logic;
   qnice_ascal_mode_o      : out std_logic_vector(1 downto 0);
   qnice_ascal_polyphase_o : out std_logic;
   qnice_ascal_triplebuf_o : out std_logic;
   qnice_retro15kHz_o      : out std_logic;              -- 0 = normal frequency, 1 = retro 15 kHz frequency
   qnice_csync_o           : out std_logic;              -- 0 = normal HS/VS, 1 = Composite Sync  

   -- Flip joystick ports
   qnice_flip_joyports_o   : out std_logic;

   -- On-Screen-Menu selections
   qnice_osm_control_i     : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register
   qnice_gp_reg_i          : in  std_logic_vector(255 downto 0);

   -- Core-specific devices
   qnice_dev_id_i          : in  std_logic_vector(15 downto 0);
   qnice_dev_addr_i        : in  std_logic_vector(27 downto 0);
   qnice_dev_data_i        : in  std_logic_vector(15 downto 0);
   qnice_dev_data_o        : out std_logic_vector(15 downto 0);
   qnice_dev_ce_i          : in  std_logic;
   qnice_dev_we_i          : in  std_logic;
   qnice_dev_wait_o        : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- HyperRAM Clock Domain
   --------------------------------------------------------------------------------------------------------

   hr_clk_i                : in  std_logic;
   hr_rst_i                : in  std_logic;
   hr_core_write_o         : out std_logic;
   hr_core_read_o          : out std_logic;
   hr_core_address_o       : out std_logic_vector(31 downto 0);
   hr_core_writedata_o     : out std_logic_vector(15 downto 0);
   hr_core_byteenable_o    : out std_logic_vector( 1 downto 0);
   hr_core_burstcount_o    : out std_logic_vector( 7 downto 0);
   hr_core_readdata_i      : in  std_logic_vector(15 downto 0);
   hr_core_readdatavalid_i : in  std_logic;
   hr_core_waitrequest_i   : in  std_logic;
   hr_high_i               : in  std_logic;  -- Core is too fast
   hr_low_i                : in  std_logic;  -- Core is too slow

   --------------------------------------------------------------------------------------------------------
   -- Video Clock Domain
   --------------------------------------------------------------------------------------------------------

   video_clk_o             : out std_logic;
   video_rst_o             : out std_logic;
   video_ce_o              : out std_logic;
   video_ce_ovl_o          : out std_logic;
   video_red_o             : out std_logic_vector(7 downto 0);
   video_green_o           : out std_logic_vector(7 downto 0);
   video_blue_o            : out std_logic_vector(7 downto 0);
   video_vs_o              : out std_logic;
   video_hs_o              : out std_logic;
   video_hblank_o          : out std_logic;
   video_vblank_o          : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- Core Clock Domain
   --------------------------------------------------------------------------------------------------------

   clk_i                   : in  std_logic;              -- 100 MHz clock

   -- Share clock and reset with the framework
   main_clk_o              : out std_logic;              -- 57.27 MHz main clock (framework and video)
   main_rst_o              : out std_logic;              -- CORE's reset, synchronized

   -- M2M's reset manager provides 2 signals:
   --    m2m:   Reset the whole machine: Core and Framework
   --    core:  Only reset the core
   main_reset_m2m_i        : in  std_logic;
   main_reset_core_i       : in  std_logic;

   main_pause_core_i       : in  std_logic;

   -- On-Screen-Menu selections
   main_osm_control_i      : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register converted to main clock domain
   main_qnice_gp_reg_i     : in  std_logic_vector(255 downto 0);

   -- Audio output (Signed PCM)
   main_audio_left_o       : out signed(15 downto 0);
   main_audio_right_o      : out signed(15 downto 0);

   -- M2M Keyboard interface (incl. power led and drive led)
   main_kb_key_num_i       : in  integer range 0 to 79;  -- cycles through all MEGA65 keys
   main_kb_key_pressed_n_i : in  std_logic;              -- low active: debounced feedback: is kb_key_num_i pressed right now?
   main_power_led_o        : out std_logic;
   main_power_led_col_o    : out std_logic_vector(23 downto 0);
   main_drive_led_o        : out std_logic;
   main_drive_led_col_o    : out std_logic_vector(23 downto 0);

   -- Joysticks and paddles input
   main_joy_1_up_n_i       : in  std_logic;
   main_joy_1_down_n_i     : in  std_logic;
   main_joy_1_left_n_i     : in  std_logic;
   main_joy_1_right_n_i    : in  std_logic;
   main_joy_1_fire_n_i     : in  std_logic;
   main_joy_1_up_n_o       : out std_logic;
   main_joy_1_down_n_o     : out std_logic;
   main_joy_1_left_n_o     : out std_logic;
   main_joy_1_right_n_o    : out std_logic;
   main_joy_1_fire_n_o     : out std_logic;
   main_joy_2_up_n_i       : in  std_logic;
   main_joy_2_down_n_i     : in  std_logic;
   main_joy_2_left_n_i     : in  std_logic;
   main_joy_2_right_n_i    : in  std_logic;
   main_joy_2_fire_n_i     : in  std_logic;
   main_joy_2_up_n_o       : out std_logic;
   main_joy_2_down_n_o     : out std_logic;
   main_joy_2_left_n_o     : out std_logic;
   main_joy_2_right_n_o    : out std_logic;
   main_joy_2_fire_n_o     : out std_logic;

   main_pot1_x_i           : in  std_logic_vector(7 downto 0);
   main_pot1_y_i           : in  std_logic_vector(7 downto 0);
   main_pot2_x_i           : in  std_logic_vector(7 downto 0);
   main_pot2_y_i           : in  std_logic_vector(7 downto 0);
   main_rtc_i              : in  std_logic_vector(64 downto 0);

   -- CBM-488/IEC serial port
   iec_reset_n_o           : out std_logic;
   iec_atn_n_o             : out std_logic;
   iec_clk_en_o            : out std_logic;
   iec_clk_n_i             : in  std_logic;
   iec_clk_n_o             : out std_logic;
   iec_data_en_o           : out std_logic;
   iec_data_n_i            : in  std_logic;
   iec_data_n_o            : out std_logic;
   iec_srq_en_o            : out std_logic;
   iec_srq_n_i             : in  std_logic;
   iec_srq_n_o             : out std_logic;

   -- C64 Expansion Port (aka Cartridge Port)
   cart_en_o               : out std_logic;  -- Enable port, active high
   cart_phi2_o             : out std_logic;
   cart_dotclock_o         : out std_logic;
   cart_dma_i              : in  std_logic;
   cart_reset_oe_o         : out std_logic;
   cart_reset_i            : in  std_logic;
   cart_reset_o            : out std_logic;
   cart_game_oe_o          : out std_logic;
   cart_game_i             : in  std_logic;
   cart_game_o             : out std_logic;
   cart_exrom_oe_o         : out std_logic;
   cart_exrom_i            : in  std_logic;
   cart_exrom_o            : out std_logic;
   cart_nmi_oe_o           : out std_logic;
   cart_nmi_i              : in  std_logic;
   cart_nmi_o              : out std_logic;
   cart_irq_oe_o           : out std_logic;
   cart_irq_i              : in  std_logic;
   cart_irq_o              : out std_logic;
   cart_roml_oe_o          : out std_logic;
   cart_roml_i             : in  std_logic;
   cart_roml_o             : out std_logic;
   cart_romh_oe_o          : out std_logic;
   cart_romh_i             : in  std_logic;
   cart_romh_o             : out std_logic;
   cart_ctrl_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_ba_i               : in  std_logic;
   cart_rw_i               : in  std_logic;
   cart_io1_i              : in  std_logic;
   cart_io2_i              : in  std_logic;
   cart_ba_o               : out std_logic;
   cart_rw_o               : out std_logic;
   cart_io1_o              : out std_logic;
   cart_io2_o              : out std_logic;
   cart_addr_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_a_i                : in  unsigned(15 downto 0);
   cart_a_o                : out unsigned(15 downto 0);
   cart_data_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_d_i                : in  unsigned( 7 downto 0);
   cart_d_o                : out unsigned( 7 downto 0)
);
end entity MEGA65_Core;

architecture synthesis of MEGA65_Core is

---------------------------------------------------------------------------------------------
-- Clocks and active high reset signals for each clock domain
---------------------------------------------------------------------------------------------

signal main_clk               : std_logic;               -- 57.27 MHz (framework, video)
signal main_rst               : std_logic;
signal cpu_clk                : std_logic;               -- 3.58 MHz (Atari colour clock)
signal cpu_phase              : unsigned(3 downto 0);

---------------------------------------------------------------------------------------------
-- Options menu items (0-based line numbers in config.vhd's OPTM_ITEMS)
---------------------------------------------------------------------------------------------

constant C_MENU_CT_AUTO       : natural := 6;            -- cartridge type: 6 .. 19
constant C_MENU_CT_F8         : natural := 7;
constant C_MENU_CT_F6         : natural := 8;
constant C_MENU_CT_F4         : natural := 9;
constant C_MENU_CT_FE         : natural := 10;
constant C_MENU_CT_E0         : natural := 11;
constant C_MENU_CT_3F         : natural := 12;
constant C_MENU_CT_FA         : natural := 13;
constant C_MENU_CT_CV         : natural := 14;
constant C_MENU_CT_UA         : natural := 15;
constant C_MENU_CT_E7         : natural := 16;
constant C_MENU_CT_F0         : natural := 17;
constant C_MENU_CT_P2         : natural := 18;
constant C_MENU_CT_32         : natural := 19;
constant C_MENU_SC_OFF        : natural := 26;
constant C_MENU_SC_ON         : natural := 27;
constant C_MENU_DIF_P1_A      : natural := 31;
constant C_MENU_DIF_P2_A      : natural := 32;
constant C_MENU_BW            : natural := 33;
constant C_MENU_PADDLES       : natural := 39;
constant C_MENU_PADDLES_INV   : natural := 41;
constant C_MENU_SWAP_JOY      : natural := 42;
constant C_MENU_PAL           : natural := 49;
constant C_MENU_VBL_ORIG      : natural := 51;
constant C_MENU_DECOMB        : natural := 52;
constant C_MENU_STEREO        : natural := 53;
constant C_MENU_IMPROVE_AUDIO : natural := 54;
constant C_MENU_CRT_EMULATION : natural := 55;
constant C_MENU_HDMI_ZOOM     : natural := 56;
constant C_MENU_HDMI_16_9_50  : natural := 62;
constant C_MENU_HDMI_16_9_60  : natural := 63;
constant C_MENU_HDMI_4_3_50   : natural := 64;
constant C_MENU_HDMI_5_4_50   : natural := 65;
constant C_MENU_HDMI_640_60   : natural := 66;
constant C_MENU_HDMI_720_5994 : natural := 67;
constant C_MENU_SVGA_800_60   : natural := 68;

-- Bank switching schemes as numbered by A2601top.vhd (force_bs)
constant C_BS_AUTO            : std_logic_vector(3 downto 0) := "0000";
constant C_BS_F8              : std_logic_vector(3 downto 0) := "0001";
constant C_BS_F6              : std_logic_vector(3 downto 0) := "0010";
constant C_BS_FE              : std_logic_vector(3 downto 0) := "0011";
constant C_BS_E0              : std_logic_vector(3 downto 0) := "0100";
constant C_BS_3F              : std_logic_vector(3 downto 0) := "0101";
constant C_BS_F4              : std_logic_vector(3 downto 0) := "0110";
constant C_BS_P2              : std_logic_vector(3 downto 0) := "0111";
constant C_BS_FA              : std_logic_vector(3 downto 0) := "1000";
constant C_BS_CV              : std_logic_vector(3 downto 0) := "1001";
constant C_BS_UA              : std_logic_vector(3 downto 0) := "1011";
constant C_BS_E7              : std_logic_vector(3 downto 0) := "1100";
constant C_BS_F0              : std_logic_vector(3 downto 0) := "1101";
constant C_BS_32              : std_logic_vector(3 downto 0) := "1110";

-- Boot ROM (MiSTer's rtl/rom.mif), shown until a cartridge is loaded.
-- Relative to the Vivado run directory (CORE/CORE-Rx.runs/synth_1), like the M2M firmware ROM.
constant C_BOOT_ROM           : string := "../../../CORE/vhdl/rom_boot.hex";

---------------------------------------------------------------------------------------------
-- main_clk
---------------------------------------------------------------------------------------------

signal main_force_bs          : std_logic_vector(3 downto 0);
signal main_superchip         : std_logic;
signal main_cart_loading      : std_logic;
signal main_cart_size         : std_logic_vector(16 downto 0);
signal main_cart_sc           : std_logic;
signal main_cart_bs           : std_logic_vector(3 downto 0);
signal cpu_rom_addr           : std_logic_vector(15 downto 0);
signal cpu_rom_data           : std_logic_vector(7 downto 0);

---------------------------------------------------------------------------------------------
-- qnice_clk
---------------------------------------------------------------------------------------------

signal qnice_cart_ce          : std_logic;
signal qnice_cart_we          : std_logic;
signal qnice_cart_data        : std_logic_vector(15 downto 0);

begin

   hr_core_write_o      <= '0';
   hr_core_read_o       <= '0';
   hr_core_address_o    <= (others => '0');
   hr_core_writedata_o  <= (others => '0');
   hr_core_byteenable_o <= (others => '0');
   hr_core_burstcount_o <= (others => '0');

   -- Tristate all expansion port drivers that we can directly control
   cart_ctrl_oe_o       <= '0';
   cart_addr_oe_o       <= '0';
   cart_data_oe_o       <= '0';

   -- Due to a bug in the R5/R6 boards, the cartridge port needs to be enabled for joystick port 2 to work
   cart_en_o            <= '1';

   cart_reset_oe_o      <= '0';
   cart_game_oe_o       <= '0';
   cart_exrom_oe_o      <= '0';
   cart_nmi_oe_o        <= '0';
   cart_irq_oe_o        <= '0';
   cart_roml_oe_o       <= '0';
   cart_romh_oe_o       <= '0';

   cart_phi2_o          <= '0';
   cart_reset_o         <= '1';
   cart_dotclock_o      <= '0';
   cart_game_o          <= '1';
   cart_exrom_o         <= '1';
   cart_nmi_o           <= '1';
   cart_irq_o           <= '1';
   cart_roml_o          <= '0';
   cart_romh_o          <= '0';
   cart_ba_o            <= '0';
   cart_rw_o            <= '0';
   cart_io1_o           <= '0';
   cart_io2_o           <= '0';
   cart_a_o             <= (others => '0');
   cart_d_o             <= (others => '0');

   main_joy_1_up_n_o    <= '1';
   main_joy_1_down_n_o  <= '1';
   main_joy_1_left_n_o  <= '1';
   main_joy_1_right_n_o <= '1';
   main_joy_1_fire_n_o  <= '1';
   main_joy_2_up_n_o    <= '1';
   main_joy_2_down_n_o  <= '1';
   main_joy_2_left_n_o  <= '1';
   main_joy_2_right_n_o <= '1';
   main_joy_2_fire_n_o  <= '1';

   -- IEC port is not used
   iec_reset_n_o        <= '1';
   iec_atn_n_o          <= '1';
   iec_clk_en_o         <= '0';
   iec_clk_n_o          <= '1';
   iec_data_en_o        <= '0';
   iec_data_n_o         <= '1';
   iec_srq_en_o         <= '0';
   iec_srq_n_o          <= '1';

   clk_gen : entity work.clk
      port map (
         sys_clk_i         => clk_i,
         main_clk_o        => main_clk,
         main_rst_o        => main_rst,
         cpu_clk_o         => cpu_clk,
         phase_o           => cpu_phase
      ); -- clk_gen

   main_clk_o  <= main_clk;
   main_rst_o  <= main_rst;
   video_clk_o <= main_clk;
   video_rst_o <= main_rst;

   ---------------------------------------------------------------------------------------------
   -- main_clk
   ---------------------------------------------------------------------------------------------

   main_power_led_o     <= '1';
   main_power_led_col_o <= x"0000FF" when main_reset_m2m_i else x"00FF00";

   -- Drive led: lights up while a cartridge is being loaded
   main_drive_led_o     <= main_cart_loading;
   main_drive_led_col_o <= x"00FF00";

   -- Cartridge type and Superchip from the menu
   p_settings : process(main_clk)
   begin
      if rising_edge(main_clk) then
         -- Auto: the scheme detected by cart.vhd (signature scan); Superchip carts are always
         -- F8/F6/F4, i.e. "by size" (C_BS_AUTO). A menu selection overrides both.
         if main_cart_sc = '1' then
            main_force_bs <= C_BS_AUTO;
         else
            main_force_bs <= main_cart_bs;
         end if;
         if    main_osm_control_i(C_MENU_CT_F8) = '1' then main_force_bs <= C_BS_F8;
         elsif main_osm_control_i(C_MENU_CT_F6) = '1' then main_force_bs <= C_BS_F6;
         elsif main_osm_control_i(C_MENU_CT_F4) = '1' then main_force_bs <= C_BS_F4;
         elsif main_osm_control_i(C_MENU_CT_FE) = '1' then main_force_bs <= C_BS_FE;
         elsif main_osm_control_i(C_MENU_CT_E0) = '1' then main_force_bs <= C_BS_E0;
         elsif main_osm_control_i(C_MENU_CT_3F) = '1' then main_force_bs <= C_BS_3F;
         elsif main_osm_control_i(C_MENU_CT_FA) = '1' then main_force_bs <= C_BS_FA;
         elsif main_osm_control_i(C_MENU_CT_CV) = '1' then main_force_bs <= C_BS_CV;
         elsif main_osm_control_i(C_MENU_CT_UA) = '1' then main_force_bs <= C_BS_UA;
         elsif main_osm_control_i(C_MENU_CT_E7) = '1' then main_force_bs <= C_BS_E7;
         elsif main_osm_control_i(C_MENU_CT_F0) = '1' then main_force_bs <= C_BS_F0;
         elsif main_osm_control_i(C_MENU_CT_P2) = '1' then main_force_bs <= C_BS_P2;
         elsif main_osm_control_i(C_MENU_CT_32) = '1' then main_force_bs <= C_BS_32;
         end if;

         -- Superchip: Auto = detected by cart.vhd, Off, On
         if main_osm_control_i(C_MENU_SC_ON) = '1' then
            main_superchip <= '1';
         elsif main_osm_control_i(C_MENU_SC_OFF) = '1' then
            main_superchip <= '0';
         else
            main_superchip <= main_cart_sc;
         end if;
      end if;
   end process p_settings;

   i_main : entity work.main
      generic map (
         G_VDNUM              => C_VDNUM
      )
      port map (
         clk_main_i           => main_clk,
         clk_cpu_i            => cpu_clk,
         phase_i              => cpu_phase,
         reset_soft_i         => main_reset_core_i,
         reset_hard_i         => main_reset_m2m_i,
         pause_i              => main_pause_core_i,

         clk_main_speed_i     => CORE_CLK_SPEED,

         pal_i                => main_osm_control_i(C_MENU_PAL),
         mono_i               => main_osm_control_i(C_MENU_BW),
         diff_p1_a_i          => main_osm_control_i(C_MENU_DIF_P1_A),
         diff_p2_a_i          => main_osm_control_i(C_MENU_DIF_P2_A),
         decomb_i             => main_osm_control_i(C_MENU_DECOMB),
         vblank_original_i    => main_osm_control_i(C_MENU_VBL_ORIG),
         stereo_i             => main_osm_control_i(C_MENU_STEREO),
         paddles_i            => main_osm_control_i(C_MENU_PADDLES),
         paddles_invert_i     => main_osm_control_i(C_MENU_PADDLES_INV),

         cart_loading_i       => main_cart_loading,
         cart_size_i          => main_cart_size,
         force_bs_i           => main_force_bs,
         superchip_i          => main_superchip,
         rom_addr_o           => cpu_rom_addr,
         rom_data_i           => cpu_rom_data,

         video_ce_o           => video_ce_o,
         video_ce_ovl_o       => video_ce_ovl_o,
         video_red_o          => video_red_o,
         video_green_o        => video_green_o,
         video_blue_o         => video_blue_o,
         video_vs_o           => video_vs_o,
         video_hs_o           => video_hs_o,
         video_hblank_o       => video_hblank_o,
         video_vblank_o       => video_vblank_o,

         audio_left_o         => main_audio_left_o,
         audio_right_o        => main_audio_right_o,

         kb_key_num_i         => main_kb_key_num_i,
         kb_key_pressed_n_i   => main_kb_key_pressed_n_i,

         joy_1_up_n_i         => main_joy_1_up_n_i,
         joy_1_down_n_i       => main_joy_1_down_n_i,
         joy_1_left_n_i       => main_joy_1_left_n_i,
         joy_1_right_n_i      => main_joy_1_right_n_i,
         joy_1_fire_n_i       => main_joy_1_fire_n_i,

         joy_2_up_n_i         => main_joy_2_up_n_i,
         joy_2_down_n_i       => main_joy_2_down_n_i,
         joy_2_left_n_i       => main_joy_2_left_n_i,
         joy_2_right_n_i      => main_joy_2_right_n_i,
         joy_2_fire_n_i       => main_joy_2_fire_n_i,

         pot1_x_i             => main_pot1_x_i,
         pot1_y_i             => main_pot1_y_i,
         pot2_x_i             => main_pot2_x_i,
         pot2_y_i             => main_pot2_y_i
      ); -- i_main

   ---------------------------------------------------------------------------------------------
   -- Audio and video settings (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   qnice_video_mode_o <= C_VIDEO_SVGA_800_60   when qnice_osm_control_i(C_MENU_SVGA_800_60)    = '1' else
                         C_VIDEO_HDMI_720_5994 when qnice_osm_control_i(C_MENU_HDMI_720_5994)  = '1' else
                         C_VIDEO_HDMI_640_60   when qnice_osm_control_i(C_MENU_HDMI_640_60)    = '1' else
                         C_VIDEO_HDMI_5_4_50   when qnice_osm_control_i(C_MENU_HDMI_5_4_50)    = '1' else
                         C_VIDEO_HDMI_4_3_50   when qnice_osm_control_i(C_MENU_HDMI_4_3_50)    = '1' else
                         C_VIDEO_HDMI_16_9_50  when qnice_osm_control_i(C_MENU_HDMI_16_9_50)   = '1' else
                         C_VIDEO_HDMI_16_9_60;

   qnice_dvi_o                <= '0';                                         -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_scandoubler_o        <= '1';                                         -- VGA output: 31 kHz
   qnice_audio_mute_o         <= '0';
   qnice_audio_filter_o       <= qnice_osm_control_i(C_MENU_IMPROVE_AUDIO);
   qnice_zoom_crop_o          <= qnice_osm_control_i(C_MENU_HDMI_ZOOM);
   qnice_retro15kHz_o         <= '0';
   qnice_csync_o              <= '0';
   qnice_osm_cfg_scaling_o    <= (others => '1');
   qnice_ascal_mode_o         <= "00";
   qnice_ascal_polyphase_o    <= qnice_osm_control_i(C_MENU_CRT_EMULATION);
   qnice_ascal_triplebuf_o    <= '0';

   -- Swap joysticks (the framework swaps the two ports)
   qnice_flip_joyports_o      <= qnice_osm_control_i(C_MENU_SWAP_JOY);

   ---------------------------------------------------------------------------------------------
   -- Core specific device handling (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   core_specific_devices : process(all)
   begin
      qnice_dev_data_o     <= x"EEEE";
      qnice_dev_wait_o     <= '0';
      qnice_cart_ce        <= '0';
      qnice_cart_we        <= '0';

      case qnice_dev_id_i is
         when C_DEV_A26_CART =>
            qnice_cart_ce     <= qnice_dev_ce_i;
            qnice_cart_we     <= qnice_dev_we_i;
            qnice_dev_data_o  <= qnice_cart_data;

         when others => null;
      end case;
   end process core_specific_devices;

   ---------------------------------------------------------------------------------------------
   -- Cartridge: 64 KB RAM, loaded by the M2M file browser (QNICE), read by the Atari (cpu_clk)
   ---------------------------------------------------------------------------------------------

   i_cart : entity work.cart
      generic map (
         G_ROM_FILE        => C_BOOT_ROM
      )
      port map (
         qnice_clk_i       => qnice_clk_i,
         qnice_rst_i       => qnice_rst_i,
         qnice_addr_i      => qnice_dev_addr_i,
         qnice_data_i      => qnice_dev_data_i,
         qnice_data_o      => qnice_cart_data,
         qnice_ce_i        => qnice_cart_ce,
         qnice_we_i        => qnice_cart_we,

         cpu_clk_i         => cpu_clk,
         rom_addr_i        => cpu_rom_addr,
         rom_data_o        => cpu_rom_data,

         main_clk_i        => main_clk,
         main_loading_o    => main_cart_loading,
         main_size_o       => main_cart_size,
         main_sc_o         => main_cart_sc,
         main_bs_o         => main_cart_bs
      ); -- i_cart

end architecture synthesis;

