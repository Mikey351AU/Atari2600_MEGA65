----------------------------------------------------------------------------------
-- Atari 2600 for MEGA65
--
-- Wrapper for the MiSTer Atari 2600 core (Atari2600_MiSTer: A2601 by Retromaster,
-- MiSTer port by Sorgelig and others)
--
-- Clock domains:
--    clk_main_i (57.27 MHz): framework, keyboard, joysticks, video sampling, TIA colour table
--    clk_cpu_i  ( 3.58 MHz): the Atari itself (TIA colour clock), gated from clk_main_i,
--                            edges aligned with clk_main_i (see clk.vhd)
--
-- Based on the MiSTer2MEGA65 framework (sy2002 and MJoergen), licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;

entity main is
   generic (
      G_VDNUM                 : natural                     -- amount of virtual drives
   );
   port (
      clk_main_i              : in  std_logic;              -- 57.27 MHz
      clk_cpu_i               : in  std_logic;              -- 3.58 MHz
      phase_i                 : in  unsigned(3 downto 0);   -- position in the cpu_clk period (clk.vhd)
      reset_soft_i            : in  std_logic;
      reset_hard_i            : in  std_logic;
      pause_i                 : in  std_logic;

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i        : in  natural;

      -- Settings (clk_main_i domain, from the options menu)
      pal_i                   : in  std_logic;              -- 1 = PAL colours
      mono_i                  : in  std_logic;              -- 1 = black & white (console switch)
      diff_p1_a_i             : in  std_logic;              -- 1 = difficulty A for player 1 (left)
      diff_p2_a_i             : in  std_logic;              -- 1 = difficulty A for player 2 (right)
      decomb_i                : in  std_logic;
      vblank_original_i       : in  std_logic;              -- 0 = regenerate VBlank (like MiSTer's default)
      stereo_i                : in  std_logic;
      paddles_i               : in  std_logic;              -- 1 = paddles in the joystick ports
      paddles_invert_i        : in  std_logic;

      -- Cartridge (from mega65.vhd)
      cart_loading_i          : in  std_logic;              -- 1 = a cartridge is being loaded: hold reset
      cart_size_i             : in  std_logic_vector(16 downto 0);
      force_bs_i              : in  std_logic_vector(3 downto 0);
      superchip_i             : in  std_logic;
      rom_addr_o              : out std_logic_vector(15 downto 0);  -- clk_cpu_i domain
      rom_data_i              : in  std_logic_vector(7 downto 0);

      -- Video output (clk_main_i domain)
      video_ce_o              : out std_logic;
      video_ce_ovl_o          : out std_logic;
      video_red_o             : out std_logic_vector(7 downto 0);
      video_green_o           : out std_logic_vector(7 downto 0);
      video_blue_o            : out std_logic_vector(7 downto 0);
      video_vs_o              : out std_logic;
      video_hs_o              : out std_logic;
      video_hblank_o          : out std_logic;
      video_vblank_o          : out std_logic;

      -- Audio output (Signed PCM)
      audio_left_o            : out signed(15 downto 0);
      audio_right_o           : out signed(15 downto 0);

      -- M2M Keyboard interface
      kb_key_num_i            : in  integer range 0 to 79;    -- cycles through all MEGA65 keys
      kb_key_pressed_n_i      : in  std_logic;                -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i            : in  std_logic;
      joy_1_down_n_i          : in  std_logic;
      joy_1_left_n_i          : in  std_logic;
      joy_1_right_n_i         : in  std_logic;
      joy_1_fire_n_i          : in  std_logic;

      joy_2_up_n_i            : in  std_logic;
      joy_2_down_n_i          : in  std_logic;
      joy_2_left_n_i          : in  std_logic;
      joy_2_right_n_i         : in  std_logic;
      joy_2_fire_n_i          : in  std_logic;

      pot1_x_i                : in  std_logic_vector(7 downto 0);
      pot1_y_i                : in  std_logic_vector(7 downto 0);
      pot2_x_i                : in  std_logic_vector(7 downto 0);
      pot2_y_i                : in  std_logic_vector(7 downto 0)
   );
end entity main;

architecture synthesis of main is

-- keyboard (high active)
signal key_up, key_down, key_left, key_right, key_fire : std_logic;
signal key_select, key_reset                            : std_logic;

-- Atari inputs (low active, as A2601top expects)
signal p1_u, p1_d, p1_l, p1_r, p1_f                     : std_logic;
signal p2_u, p2_d, p2_l, p2_r, p2_f                     : std_logic;
signal pd_btn_1, pd_btn_2, pd_btn_3, pd_btn_4           : std_logic;
signal paddle_1, paddle_2, paddle_3, paddle_4           : std_logic_vector(7 downto 0);

signal core_reset                                       : std_logic;

-- core outputs
signal aud0, aud1                                       : std_logic_vector(3 downto 0);
signal tia_vs, tia_hs, tia_hblank, tia_vblank           : std_logic;
signal tia_r, tia_g, tia_b                              : std_logic_vector(7 downto 0);

-- video, clk_main_i domain
signal v_hs_d, v_vs_d                                   : std_logic := '0';
signal line_cnt, vblank_start                           : unsigned(8 downto 0) := (others => '0');
signal vbl_gen                                          : std_logic := '1';
signal vbl_line                                         : std_logic := '1';

begin

   ---------------------------------------------------------------------------------------------
   -- Controls
   ---------------------------------------------------------------------------------------------

   i_keyboard : entity work.keyboard
      port map (
         clk_main_i           => clk_main_i,
         key_num_i            => kb_key_num_i,
         key_pressed_n_i      => kb_key_pressed_n_i,
         key_up_o             => key_up,
         key_down_o           => key_down,
         key_left_o           => key_left,
         key_right_o          => key_right,
         key_fire_o           => key_fire,
         key_select_o         => key_select,
         key_reset_o          => key_reset
      ); -- i_keyboard

   -- Player 1: joystick port 1 or the keyboard; player 2: joystick port 2.
   -- With paddles, the joystick left/right lines are the paddle buttons (C64/Atari paddles),
   -- so the joystick inputs are switched off.
   p1_u <= '1' when paddles_i = '1' else joy_1_up_n_i    and not key_up;
   p1_d <= '1' when paddles_i = '1' else joy_1_down_n_i  and not key_down;
   p1_l <= '1' when paddles_i = '1' else joy_1_left_n_i  and not key_left;
   p1_r <= '1' when paddles_i = '1' else joy_1_right_n_i and not key_right;
   p1_f <= '1' when paddles_i = '1' else joy_1_fire_n_i  and not key_fire;

   p2_u <= '1' when paddles_i = '1' else joy_2_up_n_i;
   p2_d <= '1' when paddles_i = '1' else joy_2_down_n_i;
   p2_l <= '1' when paddles_i = '1' else joy_2_left_n_i;
   p2_r <= '1' when paddles_i = '1' else joy_2_right_n_i;
   p2_f <= '1' when paddles_i = '1' else joy_2_fire_n_i;

   pd_btn_1 <= joy_1_left_n_i  when paddles_i = '1' else '1';
   pd_btn_2 <= joy_1_right_n_i when paddles_i = '1' else '1';
   pd_btn_3 <= joy_2_left_n_i  when paddles_i = '1' else '1';
   pd_btn_4 <= joy_2_right_n_i when paddles_i = '1' else '1';

   paddle_1 <= not pot1_x_i when paddles_invert_i = '1' else pot1_x_i;
   paddle_2 <= not pot1_y_i when paddles_invert_i = '1' else pot1_y_i;
   paddle_3 <= not pot2_x_i when paddles_invert_i = '1' else pot2_x_i;
   paddle_4 <= not pot2_y_i when paddles_invert_i = '1' else pot2_y_i;

   -- MiSTer also resets the core while a cartridge is downloaded
   core_reset <= reset_soft_i or reset_hard_i or cart_loading_i;

   ---------------------------------------------------------------------------------------------
   -- The Atari 2600
   ---------------------------------------------------------------------------------------------

   i_a2601 : entity work.A2601top
      port map (
         reset     => core_reset,
         clk       => clk_cpu_i,
         vid_clk   => clk_main_i,

         aud0      => aud0,
         aud1      => aud1,

         O_VSYNC   => tia_vs,
         O_HSYNC   => tia_hs,
         O_HBLANK  => tia_hblank,
         O_VBLANK  => tia_vblank,
         O_VIDEO_R => tia_r,
         O_VIDEO_G => tia_g,
         O_VIDEO_B => tia_b,

         p1_l      => p1_l,
         p1_r      => p1_r,
         p1_u      => p1_u,
         p1_d      => p1_d,
         p1_f      => p1_f,
         p1_f2     => '1',

         p2_l      => p2_l,
         p2_r      => p2_r,
         p2_u      => p2_u,
         p2_d      => p2_d,
         p2_f      => p2_f,
         p2_f2     => '1',

         p_1       => pd_btn_1,
         paddle_1  => paddle_1,
         p_2       => pd_btn_2,
         paddle_2  => paddle_2,
         p_3       => pd_btn_3,
         paddle_3  => paddle_3,
         p_4       => pd_btn_4,
         paddle_4  => paddle_4,

         p_type    => "00",

         p_start   => not key_reset,               -- console "Game Reset" switch
         p_select  => not key_select,              -- console "Game Select" switch
         p_color   => not mono_i,

         sc        => superchip_i,
         force_bs  => force_bs_i,
         rom_a     => rom_addr_o,
         rom_do    => rom_data_i,
         rom_size  => cart_size_i,

         pause     => pause_i,

         pal       => pal_i,
         p_dif     => diff_p2_a_i & diff_p1_a_i,
         decomb    => decomb_i
      ); -- i_a2601

   ---------------------------------------------------------------------------------------------
   -- Audio: two 4-bit TIA channels. Mono (default, like MiSTer) mixes both channels.
   -- Unsigned to signed: flip the MSB.
   ---------------------------------------------------------------------------------------------

   p_audio : process(clk_main_i)
      variable mix : unsigned(4 downto 0);
   begin
      if rising_edge(clk_main_i) then
         if stereo_i = '1' then
            audio_left_o  <= signed((not aud0(3)) & aud0(2 downto 0) & aud0 & aud0 & aud0);
            audio_right_o <= signed((not aud1(3)) & aud1(2 downto 0) & aud1 & aud1 & aud1);
         else
            mix := unsigned('0' & aud0) + unsigned('0' & aud1);           -- 0 .. 30
            audio_left_o  <= signed((not mix(4)) & mix(3 downto 0) & "00000000000");
            audio_right_o <= signed((not mix(4)) & mix(3 downto 0) & "00000000000");
         end if;
      end if;
   end process p_audio;

   ---------------------------------------------------------------------------------------------
   -- Video: sample the TIA output at 4x the colour clock (14.32 MHz, 640 pixels per visible line)
   --
   -- A cpu_clk edge (new TIA pixel: sync/blank registers) happens on the main_clk edge where
   -- phase_i = 15; the TIA colour table (vid_clk = main_clk) follows one main_clk later. So on
   -- the main_clk edges where phase_i = 3, 7, 11 and 15 all signals belong to the same pixel.
   -- video_ce_ovl_o runs at 2x (every 2nd main_clk), the post-scandoubler pixel clock.
   ---------------------------------------------------------------------------------------------

   p_video : process(clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         video_ce_o     <= '0';
         video_ce_ovl_o <= phase_i(0);

         if phase_i(1 downto 0) = "11" then
            video_ce_o     <= '1';
            video_red_o    <= tia_r;
            video_green_o  <= tia_g;
            video_blue_o   <= tia_b;
            video_hs_o     <= tia_hs;
            -- VSYNC only changes at the start of a line (hsync edge, inside HBLANK). Games may
            -- write VSYNC in the middle of a line; the scaler (ascal) starts a new frame at the
            -- first visible pixel after the VSYNC edge, so a mid-line VSYNC with the picture not
            -- blanked shifts and wraps the image horizontally (Miner 2049er with Original VBlank:
            -- it sets VSYNC+VBLANK mid-line and clears VBLANK together with VSYNC).
            video_vs_o     <= v_vs_d;
            video_hblank_o <= tia_hblank;
            video_vblank_o <= vbl_line when vblank_original_i = '1' else vbl_gen;

            -- VBlank regeneration (MiSTer Atari2600.sv): games set VBLANK very differently, so by
            -- default a fixed window is used: visible from line 34 to 25 lines before VSYNC
            v_hs_d <= tia_hs;
            if v_hs_d = '0' and tia_hs = '1' then
               -- "Original VBlank": the game's own VBLANK (the TIA already latches it at the start
               -- of a line), plus always blanked during the VSYNC lines.
               vbl_line <= tia_vblank or tia_vs;
               v_vs_d   <= tia_vs;
               line_cnt <= line_cnt + 1;
               if v_vs_d = '0' and tia_vs = '1' then
                  line_cnt     <= (others => '0');
                  vblank_start <= line_cnt - 25;
               end if;
               if line_cnt = vblank_start then
                  vbl_gen <= '1';
               end if;
               if line_cnt = 34 then
                  vbl_gen <= '0';
               end if;
            end if;
         end if;
      end if;
   end process p_video;

end architecture synthesis;

