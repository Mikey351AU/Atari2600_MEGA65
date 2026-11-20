-------------------------------------------------------------------------------------------------------------
-- Atari 2600 for MEGA65
--
-- Clock generator
--
--   main_clk (57.272727 MHz) = 16 x the NTSC colour clock. Used for the framework's core clock domain,
--                              for video and for the TIA colour lookup table (MiSTer: clk_sys, 28.6 MHz)
--   cpu_clk  ( 3.579545 MHz) = main_clk gated by a BUFGCE: exactly one of 16 main_clk pulses passes.
--                              This is the Atari's colour clock (MiSTer: clk_cpu). The 7-series MMCM
--                              cannot output less than 4.69 MHz, and a BUFGCE keeps cpu_clk edges
--                              aligned with main_clk edges (same kind of global buffer, same source).
--   phase_o                  : position (0..15) inside one cpu_clk period, in the main_clk domain.
--                              A cpu_clk rising edge happens on the main_clk edge where phase_o = 15.
--
--   100 MHz / 5 (DIVCLK) * 31.5 = 630 MHz VCO; 630 / 11 = 57.272727 MHz; / 16 = 3.579545 MHz (NTSC exact)
--
-- Based on the MiSTer2MEGA65 framework template (sy2002 and MJoergen), licensed under GPL v3
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity clk is
   port (
      sys_clk_i       : in  std_logic;   -- expects 100 MHz

      main_clk_o      : out std_logic;   -- 57.272727 MHz
      main_rst_o      : out std_logic;   -- main's reset, synchronized

      cpu_clk_o       : out std_logic;   -- 3.579545 MHz (gated main_clk)
      phase_o         : out unsigned(3 downto 0)
   );
end entity clk;

architecture rtl of clk is

signal clkfb_mmcm         : std_logic;
signal clkfb              : std_logic;
signal main_clk_mmcm      : std_logic;
signal main_clk           : std_logic;
signal locked             : std_logic;
signal main_rst           : std_logic;

signal phase              : unsigned(3 downto 0) := (others => '0');
signal cpu_ce             : std_logic := '0';

begin

   i_clk_main : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 5,          -- 20 MHz PFD
         CLKFBOUT_MULT_F      => 31.500,     -- 630 MHz VCO
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 11.000,     -- 57.272727 MHz
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE
      )
      port map (
         CLKFBOUT            => clkfb_mmcm,
         CLKOUT0             => main_clk_mmcm,
         CLKFBIN             => clkfb,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         CLKINSEL            => '1',
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         LOCKED              => locked,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_main

   clkfb_bufg : BUFG
      port map (
         I => clkfb_mmcm,
         O => clkfb
      );

   main_clk_bufg : BUFG
      port map (
         I => main_clk_mmcm,
         O => main_clk
      );

   -- cpu_clk: one of 16 main_clk pulses. cpu_ce is high during the main_clk cycle in which
   -- phase = 15, so the BUFGCE passes the main_clk edge at the end of that cycle.
   cpu_clk_bufgce : BUFGCE
      port map (
         I  => main_clk_mmcm,
         CE => cpu_ce,
         O  => cpu_clk_o
      );

   p_phase : process(main_clk)
   begin
      if rising_edge(main_clk) then
         phase  <= phase + 1;
         cpu_ce <= '1' when phase = 14 else '0';
      end if;
   end process p_phase;

   main_clk_o <= main_clk;
   phase_o    <= phase;

   i_xpm_cdc_async_rst_main : xpm_cdc_async_rst
      generic map (
         RST_ACTIVE_HIGH => 1,
         DEST_SYNC_FF    => 6
      )
      port map (
         src_arst  => not locked,
         dest_clk  => main_clk,
         dest_arst => main_rst
      );

   main_rst_o <= main_rst;

end architecture rtl;

