----------------------------------------------------------------------------------
-- Atari 2600 for MEGA65
--
-- Cartridge device: 64 KB cartridge RAM plus the M2M "manually loadable ROM" protocol
--
-- QNICE side (device as configured in globals.vhd, C_CRTROMS_MAN):
--    4k windows 0x0000 .. 0x000F: cartridge data, one byte per address (written by the M2M file loader)
--    4k window  0xFFFF          : control and status registers (CSR), see M2M/rom/sysdef.asm:
--       0x000 status (QNICE -> device): 0=idle, 1=loading, 2=error, 3=ok (loading finished)
--       0x001 file size, low word      0x002 file size, high word
--       0x010 parse status (device -> QNICE): 0=idle, 1=parsing, 2=ok, 3=error
--       0x011 error code               0x012/0x013 load address (always 0)
--       0x100 error string (zero terminated)
--
-- When QNICE reports "ok", the "parser" checks the size (1 .. 64 KB), detects the bank switching
-- scheme from typical code signatures (like Stella's CartDetector: E0, 3F, UA, FE, E7, CV, and
-- DPC by size) and detects Superchip
-- cartridges the way Stella does: an 8K/16K/32K cartridge with Superchip RAM has identical bytes
-- in 0x000-0x07F and 0x080-0x0FF of every 4K bank (the dump of the RAM's write and read ports).
--
-- Core side: the cartridge RAM read port runs on cpu_clk (like MiSTer's rom[] with registered
-- address on clk_cpu). Status signals are synchronized into the main clock domain.
--
-- Licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

entity cart is
   generic (
      G_ROM_FILE        : string                                -- boot ROM shown before a cartridge is loaded
   );
   port (
      -- QNICE clock domain
      qnice_clk_i       : in  std_logic;
      qnice_rst_i       : in  std_logic;
      qnice_addr_i      : in  std_logic_vector(27 downto 0);
      qnice_data_i      : in  std_logic_vector(15 downto 0);
      qnice_data_o      : out std_logic_vector(15 downto 0);
      qnice_ce_i        : in  std_logic;
      qnice_we_i        : in  std_logic;

      -- Atari clock domain: cartridge ROM
      cpu_clk_i         : in  std_logic;
      rom_addr_i        : in  std_logic_vector(15 downto 0);
      rom_data_o        : out std_logic_vector(7 downto 0);

      -- main clock domain: status
      main_clk_i        : in  std_logic;
      main_loading_o    : out std_logic;                        -- hold the Atari in reset
      main_size_o       : out std_logic_vector(16 downto 0);    -- 0 = boot ROM (treated as 4K)
      main_sc_o         : out std_logic;                        -- Superchip detected
      main_bs_o         : out std_logic_vector(3 downto 0)      -- detected bank switching (A2601top numbering, 0 = by size)
   );
end entity cart;

architecture synthesis of cart is

   constant C_ST_IDLE   : std_logic_vector(15 downto 0) := x"0000";
   constant C_ST_LDNG   : std_logic_vector(15 downto 0) := x"0001";
   constant C_ST_ERR    : std_logic_vector(15 downto 0) := x"0002";
   constant C_ST_OK     : std_logic_vector(15 downto 0) := x"0003";

   constant C_PT_IDLE   : std_logic_vector(15 downto 0) := x"0000";
   constant C_PT_PRSNG  : std_logic_vector(15 downto 0) := x"0001";
   constant C_PT_OK     : std_logic_vector(15 downto 0) := x"0002";
   constant C_PT_ERR    : std_logic_vector(15 downto 0) := x"0003";

   constant C_ERR_EMPTY : string := "Empty file";
   constant C_ERR_LARGE : string := "Too large: max. 64 KB";

   -- Bank switching schemes as numbered by A2601top.vhd (force_bs); "0000" = by size
   constant C_BS_SIZE   : std_logic_vector(3 downto 0) := "0000";
   constant C_BS_FE     : std_logic_vector(3 downto 0) := "0011";
   constant C_BS_E0     : std_logic_vector(3 downto 0) := "0100";
   constant C_BS_3F     : std_logic_vector(3 downto 0) := "0101";
   constant C_BS_P2     : std_logic_vector(3 downto 0) := "0111";
   constant C_BS_CV     : std_logic_vector(3 downto 0) := "1001";
   constant C_BS_UA     : std_logic_vector(3 downto 0) := "1011";
   constant C_BS_E7     : std_logic_vector(3 downto 0) := "1100";

   type state_t is (S_IDLE, S_CHECK, S_SIG_RUN, S_SIG_DECIDE, S_SC_ADDR, S_SC_READ1, S_SC_READ2, S_SETTLE);
   signal state         : state_t := S_IDLE;

   signal csr_status    : std_logic_vector(15 downto 0) := C_ST_IDLE;
   signal csr_fs_lo     : std_logic_vector(15 downto 0) := (others => '0');
   signal csr_fs_hi     : std_logic_vector(15 downto 0) := (others => '0');
   signal parse_st      : std_logic_vector(15 downto 0) := C_PT_IDLE;
   signal parse_err     : std_logic_vector(15 downto 0) := (others => '0');

   signal loading       : std_logic := '0';
   signal size          : std_logic_vector(16 downto 0) := (others => '0');
   signal sc_detected   : std_logic := '0';

   -- Superchip scan
   signal scan_bank     : unsigned(2 downto 0);
   signal scan_banks    : unsigned(3 downto 0);
   signal scan_idx      : unsigned(6 downto 0);
   signal scan_byte1    : std_logic_vector(7 downto 0);
   signal settle_cnt    : unsigned(4 downto 0);

   -- Bank switching detection (signature scan, like Stella's CartDetector)
   signal sig_sr        : std_logic_vector(31 downto 0) := (others => '0');   -- previous 4 bytes
   signal sig_cnt       : unsigned(16 downto 0);
   signal hit_e0        : std_logic;
   signal hit_3f        : unsigned(1 downto 0);                               -- saturates at 2
   signal hit_ua        : std_logic;
   signal hit_fe        : std_logic;
   signal hit_e7        : std_logic;
   signal hit_cv        : std_logic;
   signal cart_bs       : std_logic_vector(3 downto 0) := C_BS_SIZE;

   -- cartridge RAM port A (QNICE)
   signal is_csr        : std_logic;
   signal ram_we        : std_logic;
   signal ram_addr_a    : std_logic_vector(15 downto 0);
   signal ram_q_a       : std_logic_vector(7 downto 0);
   signal scan_addr     : std_logic_vector(15 downto 0) := (others => '0');

   signal main_sync     : std_logic_vector(22 downto 0);

   pure function str_char(s : string; i : natural) return std_logic_vector is
   begin
      if i < s'length then
         return std_logic_vector(to_unsigned(character'pos(s(s'low + i)), 16));
      else
         return x"0000";
      end if;
   end function str_char;

begin

   is_csr     <= '1' when qnice_addr_i(27 downto 12) = x"FFFF" else '0';
   ram_we     <= '1' when qnice_ce_i = '1' and qnice_we_i = '1' and is_csr = '0' and
                          qnice_addr_i(27 downto 16) = x"000" else '0';
   ram_addr_a <= qnice_addr_i(15 downto 0) when state = S_IDLE else scan_addr;

   ---------------------------------------------------------------------------------------------
   -- Cartridge RAM: port A = QNICE (falling edge, M2M convention), port B = Atari (cpu_clk)
   ---------------------------------------------------------------------------------------------

   i_cart_ram : entity work.dualport_2clk_ram
      generic map (
         ADDR_WIDTH     => 16,
         DATA_WIDTH     => 8,
         ROM_PRELOAD    => true,
         ROM_FILE       => G_ROM_FILE,
         ROM_FILE_HEX   => true,
         FALLING_A      => true
      )
      port map (
         clock_a        => qnice_clk_i,
         address_a      => ram_addr_a,
         data_a         => qnice_data_i(7 downto 0),
         wren_a         => ram_we,
         q_a            => ram_q_a,

         clock_b        => cpu_clk_i,
         address_b      => rom_addr_i,
         data_b         => (others => '0'),
         wren_b         => '0',
         q_b            => rom_data_o
      ); -- i_cart_ram

   ---------------------------------------------------------------------------------------------
   -- CSR read
   ---------------------------------------------------------------------------------------------

   p_read : process(all)
      variable idx : natural;
   begin
      qnice_data_o <= x"EEEE";
      idx := to_integer(unsigned(qnice_addr_i(7 downto 0)));
      if is_csr = '1' then
         case qnice_addr_i(11 downto 0) is
            when x"000" => qnice_data_o <= csr_status;
            when x"001" => qnice_data_o <= csr_fs_lo;
            when x"002" => qnice_data_o <= csr_fs_hi;
            when x"010" => qnice_data_o <= parse_st;
            when x"011" => qnice_data_o <= parse_err;
            when x"012" => qnice_data_o <= x"0000";
            when x"013" => qnice_data_o <= x"0000";
            when others =>
               if qnice_addr_i(11 downto 8) = x"1" then
                  if parse_err = x"0001" then
                     qnice_data_o <= str_char(C_ERR_EMPTY, idx);
                  else
                     qnice_data_o <= str_char(C_ERR_LARGE, idx);
                  end if;
               end if;
         end case;
      else
         qnice_data_o <= x"00" & ram_q_a;
      end if;
   end process p_read;

   ---------------------------------------------------------------------------------------------
   -- CSR write and parser
   ---------------------------------------------------------------------------------------------

   p_csr : process(qnice_clk_i)
      variable fs : unsigned(31 downto 0);
      variable w  : std_logic_vector(39 downto 0);
      variable sz : natural range 0 to 131071;
   begin
      if rising_edge(qnice_clk_i) then
         if qnice_ce_i = '1' and qnice_we_i = '1' and is_csr = '1' then
            case qnice_addr_i(11 downto 0) is
               when x"000" =>
                  csr_status <= qnice_data_i;
                  if qnice_data_i = C_ST_LDNG then
                     loading  <= '1';
                     parse_st <= C_PT_IDLE;
                  elsif qnice_data_i = C_ST_OK then
                     loading  <= '1';
                     parse_st <= C_PT_PRSNG;
                     state    <= S_CHECK;
                  else
                     loading  <= '0';                       -- idle or error: run the previous content
                  end if;
               when x"001" => csr_fs_lo <= qnice_data_i;
               when x"002" => csr_fs_hi <= qnice_data_i;
               when others => null;
            end case;
         end if;

         case state is
            when S_IDLE =>
               null;

            when S_CHECK =>
               fs := unsigned(csr_fs_hi) & unsigned(csr_fs_lo);
               if fs = 0 then
                  parse_err <= x"0001";
                  parse_st  <= C_PT_ERR;
                  loading   <= '0';
                  state     <= S_IDLE;
               elsif fs > 65536 then
                  parse_err <= x"0002";
                  parse_st  <= C_PT_ERR;
                  loading   <= '0';
                  state     <= S_IDLE;
               else
                  parse_err   <= x"0000";
                  size        <= std_logic_vector(fs(16 downto 0));
                  sc_detected <= '0';
                  cart_bs     <= C_BS_SIZE;
                  hit_e0      <= '0';
                  hit_3f      <= (others => '0');
                  hit_ua      <= '0';
                  hit_fe      <= '0';
                  hit_e7      <= '0';
                  hit_cv      <= '0';
                  sig_sr      <= (others => '0');
                  sig_cnt     <= (others => '0');
                  scan_addr   <= (others => '0');      -- first byte arrives in S_SIG_RUN
                  if fs <= 32768 then
                     state <= S_SIG_RUN;
                  else
                     state <= S_SIG_DECIDE;             -- 64K: by size (like MiSTer)
                  end if;
               end if;

            -- Signature scan: one byte per clock. The RAM latches scan_addr on the falling edge,
            -- so on every rising edge ram_q_a holds the byte at the address set one clock earlier.
            -- Window w = previous 4 bytes & current byte (current byte = w(7 downto 0)).
            -- Signatures from Stella's CartDetector (isProbablyE0/3F/UA/FE/E7/CV).
            when S_SIG_RUN =>
               w := sig_sr & ram_q_a;

               -- E0 (Parker Brothers): STA $1FE0, STA $5FE0, STA $FFE9, NOP $1FE0, LDA $1FE0,
               --                       LDA $FFE9, LDA $FFED, LDA $BFF3
               if w(23 downto 0) = x"8DE01F" or w(23 downto 0) = x"8DE05F" or
                  w(23 downto 0) = x"8DE9FF" or w(23 downto 0) = x"0CE01F" or
                  w(23 downto 0) = x"ADE01F" or w(23 downto 0) = x"ADE9FF" or
                  w(23 downto 0) = x"ADEDFF" or w(23 downto 0) = x"ADF3BF" then
                  hit_e0 <= '1';
               end if;

               -- 3F (Tigervision): STA $3F, at least twice
               if w(15 downto 0) = x"853F" and hit_3f /= 2 then
                  hit_3f <= hit_3f + 1;
               end if;

               -- UA (UA Limited): STA $240, LDA $240, LDA $21F,X
               if w(23 downto 0) = x"8D4002" or w(23 downto 0) = x"AD4002" or
                  w(23 downto 0) = x"BD1F02" then
                  hit_ua <= '1';
               end if;

               -- FE (Activision 8K): JSR $D000 / DEC $C5, JSR $F8C3 / LDA $82,
               --                     BNE / JSR $FE73, JSR $F000 / STY $D6
               if w = x"2000D0C6C5" or w = x"20C3F8A582" or
                  w = x"D0FB2073FE" or w = x"2000F084D6" then
                  hit_fe <= '1';
               end if;

               -- E7 (M-Network): LDA $FFE2, LDA $FFE5, LDA $1FE5, LDA $1FE7, NOP $1FE7,
               --                 STA $FFE7, STA $1FE7
               if w(23 downto 0) = x"ADE2FF" or w(23 downto 0) = x"ADE5FF" or
                  w(23 downto 0) = x"ADE51F" or w(23 downto 0) = x"ADE71F" or
                  w(23 downto 0) = x"0CE71F" or w(23 downto 0) = x"8DE7FF" or
                  w(23 downto 0) = x"8DE71F" then
                  hit_e7 <= '1';
               end if;

               -- CV (Commavid): STA $F3FF,X, STA $F400,Y
               if w(23 downto 0) = x"9DFFF3" or w(23 downto 0) = x"9900F4" then
                  hit_cv <= '1';
               end if;

               sig_sr    <= w(31 downto 0);
               scan_addr <= std_logic_vector(unsigned(scan_addr) + 1);
               if sig_cnt = unsigned(size) - 1 then
                  state <= S_SIG_DECIDE;
               else
                  sig_cnt <= sig_cnt + 1;
               end if;

            -- Choose the scheme. The MiSTer core supports E0, 3F, UA and FE with 8K, E7 with
            -- 16K and CV with 2K. "By size" keeps MiSTer's behaviour (F8, F6, F4, FA, ...).
            when S_SIG_DECIDE =>
               sz := to_integer(unsigned(size));
               if (sz = 2048 or sz = 4096) and hit_cv = '1' then
                  cart_bs <= C_BS_CV;
               elsif sz = 8192 and hit_e0 = '1' then
                  cart_bs <= C_BS_E0;
               elsif sz = 8192 and hit_3f = 2 then
                  cart_bs <= C_BS_3F;
               elsif sz = 8192 and hit_ua = '1' then
                  cart_bs <= C_BS_UA;
               elsif sz = 8192 and hit_fe = '1' then
                  cart_bs <= C_BS_FE;
               elsif sz >= 10240 and sz <= 10495 then
                  cart_bs <= C_BS_P2;                   -- Pitfall II: 8K + 2K DPC graphics (+ 255)
               elsif sz = 16384 and hit_e7 = '1' then
                  cart_bs <= C_BS_E7;
               else
                  cart_bs <= C_BS_SIZE;
               end if;

               if sz = 8192 or sz = 16384 or sz = 32768 then
                  sc_detected <= '1';                    -- until a mismatch is found
                  scan_banks  <= resize(to_unsigned(sz / 4096, 4), 4);
                  scan_bank   <= (others => '0');
                  scan_idx    <= (others => '0');
                  state       <= S_SC_ADDR;
               else
                  settle_cnt <= (others => '1');
                  state      <= S_SETTLE;
               end if;

            -- compare byte (bank*4096 + idx) with byte (bank*4096 + 128 + idx)
            when S_SC_ADDR =>
               scan_addr <= '0' & std_logic_vector(scan_bank) & x"0" & '0' & std_logic_vector(scan_idx);
               state     <= S_SC_READ1;

            when S_SC_READ1 =>                               -- RAM latches the address on the falling edge
               scan_byte1 <= ram_q_a;
               scan_addr  <= '0' & std_logic_vector(scan_bank) & x"0" & '1' & std_logic_vector(scan_idx);
               state      <= S_SC_READ2;

            when S_SC_READ2 =>
               if ram_q_a /= scan_byte1 then
                  sc_detected <= '0';
                  settle_cnt  <= (others => '1');
                  state       <= S_SETTLE;
               elsif scan_idx /= 127 then
                  scan_idx <= scan_idx + 1;
                  state    <= S_SC_ADDR;
               elsif ('0' & scan_bank) /= scan_banks - 1 then
                  scan_idx  <= (others => '0');
                  scan_bank <= scan_bank + 1;
                  state     <= S_SC_ADDR;
               else
                  settle_cnt <= (others => '1');
                  state      <= S_SETTLE;
               end if;

            -- give the size/Superchip results time to cross into the main clock domain before
            -- the reset is released
            when S_SETTLE =>
               if settle_cnt = 0 then
                  parse_st <= C_PT_OK;
                  loading  <= '0';
                  state    <= S_IDLE;
               else
                  settle_cnt <= settle_cnt - 1;
               end if;
         end case;

         if qnice_rst_i = '1' then
            state      <= S_IDLE;
            csr_status <= C_ST_IDLE;
            parse_st   <= C_PT_IDLE;
            loading    <= '0';
         end if;
      end if;
   end process p_csr;

   ---------------------------------------------------------------------------------------------
   -- Status into the main clock domain (quasi static signals)
   ---------------------------------------------------------------------------------------------

   i_cdc_status : xpm_cdc_array_single
      generic map (
         DEST_SYNC_FF   => 3,
         SRC_INPUT_REG  => 1,
         WIDTH          => 23
      )
      port map (
         src_clk        => qnice_clk_i,
         src_in         => cart_bs & loading & sc_detected & size,
         dest_clk       => main_clk_i,
         dest_out       => main_sync
      ); -- i_cdc_status

   main_bs_o      <= main_sync(22 downto 19);
   main_loading_o <= main_sync(18);
   main_sc_o      <= main_sync(17);
   main_size_o    <= main_sync(16 downto 0);

end architecture synthesis;

