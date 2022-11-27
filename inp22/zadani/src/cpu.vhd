-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
  signal pc : std_logic_vector(12 downto 0);
  signal pc_inc : std_logic;
  signal pc_dec : std_logic;
  signal pc_jmp : std_logic;

  signal ptr : std_logic_vector(12 downto 0);
  signal ptr_inc : std_logic;
  signal ptr_dec : std_logic;
  signal ptr_do_wh: std_logic_vector(12 downto 0);

  signal cnt : std_logic_vector(7 downto 0);
  signal cnt_inc : std_logic;
  signal cnt_dec : std_logic;

  signal mxslc_1 : std_logic;
  signal mxslc_2 : std_logic_vector(1 downto 0);

  type fsm is (
    sIdle,
    sFetch,
    sDecode,
    sDec_addr, -- <
    sInc_addr, -- >
    sDec_data, -- -
    sDec_dataC,
    sInc_data, -- +
    sInc_dataC,
    sWhile_init, -- [
    sWhile,
    sWhile2,
    sWhile3,
    sWhile_end, -- ]
    sWhile_end1,
    sWhile_end2,
    sWhile_end3,
    sPrint, -- .
    sPrintC,
    sLoad, -- ,
    sLoadC,
    sDoWhile_init, -- (
    sDoWhile_end, -- )
    sDoWhile,
    sOther,
    sNull
  );
  signal state: fsm;
  signal nextState: fsm;

begin

  pc_cntr: process(RESET, CLK)
  begin
    if (RESET='1') then
      pc <= (others=>'0');
    elsif (CLK'event) and (CLK='1') then
      if (pc_inc='1') then
        pc <= pc + 1;
      elsif (pc_dec='1') then
        pc <= pc - 1;
      elsif (pc_jmp = '1') then
        pc <= ptr_do_wh;
      end if;
    end if;
  end process; 

  ptr_cntr: process(RESET, CLK)
  begin
    if RESET = '1' then
      ptr <= "1000000000000";
    elsif (CLK'event) and (CLK='1') then
      if ptr_inc = '1' then
        ptr <= ptr + 1;
      elsif (ptr_dec='1') then
        ptr <= ptr - 1;
      end if;
    end if;
  end process;

  cnt_cntr: process(RESET, CLK)
  begin
    if RESET = '1' then
      cnt <= (others=>'0');
    elsif (CLK'event) and (CLK='1') then
      if cnt_inc = '1' then
        cnt <= cnt + 1;
      elsif (cnt_dec='1') then
        cnt <= cnt - 1;
      end if;
    end if;
  end process;  

  mx1: process(CLK, pc, ptr, mxslc_1)
  begin
    case mxslc_1 is
      when '0' => DATA_ADDR <= pc;
      when '1' => DATA_ADDR <= ptr;
      when others =>
    end case;
  end process;

  mx2: process(CLK, mxslc_2, IN_DATA, DATA_RDATA)
  begin
    case mxslc_2 is
      when "00" => DATA_WDATA <= IN_DATA;
      when "01" => DATA_WDATA <= DATA_RDATA - 1;
      when "10" => DATA_WDATA <= DATA_RDATA + 1;
      when others =>
    end case;
  end process;


  fsm_pstate: process (RESET, CLK)
  begin
    if (RESET='1') then
      state <= sIdle;
    elsif (CLK'event) and (CLK='1') then
      if (EN = '1') then
        state <= nextState;
      end if;
    end if;
  end process;

  next_state_logic : process(IN_VLD, OUT_BUSY, DATA_RDATA, cnt, state)
        begin
          OUT_WE <= '0';
          IN_REQ <= '0';
          pc_inc <= '0';
          pc_dec <= '0';
          pc_jmp <= '0';
          cnt_inc <= '0';
          cnt_dec <= '0';
          ptr_inc <= '0';
          ptr_dec <= '0';
          DATA_RDWR <= '0';
          DATA_EN <= '0';
          mxslc_2 <= "00";

          case state is
            when sIdle =>
              nextState <= sFetch;

            when sFetch =>
              mxslc_1 <= '0';
              DATA_EN <= '1';
              nextState <= sDecode;

            when sDecode =>
              mxslc_1 <= '0';
              case DATA_RDATA is
                when X"3E" => nextState <= sInc_addr;
                when X"3C" => nextState <= sDec_addr;
                when X"2B" => nextState <= sInc_data;
                when X"2D" => nextState <= sDec_data;
                when X"5B" => nextState <= sWhile_init;
                when X"5D" => nextState <= sWhile_end; 
                when X"28" => nextState <= sDoWhile_init;
                when X"29" => nextState <= sDoWhile_end;
                when X"2E" => nextState <= sPrint;
                when X"2C" => nextState <= sLoad;
                when X"00" => nextState <= sNull;
                when others => nextState <= sOther;
              end case;
            
            
            when sInc_addr =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '1';
              ptr_inc <= '1';
              pc_inc <= '1';
              nextState <= sFetch;

            when sDec_addr =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '1';
              ptr_dec <= '1';
              pc_inc <= '1';
              nextState <= sFetch;

            when sInc_data =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '1';
              nextState <= sInc_dataC;

            when sInc_dataC =>
              DATA_EN <= '1';
              DATA_RDWR <= '1';
              mxslc_1 <= '1';
              mxslc_2 <= "10";
              pc_inc <= '1';
              nextState <= sFetch;

            when sDec_data =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '1';
              nextState <= sDec_dataC;

            when sDec_dataC =>
              DATA_EN <= '1';
              DATA_RDWR <= '1';
              mxslc_1 <= '1';
              mxslc_2 <= "01";
              pc_inc <= '1';
              nextState <= sFetch;
            
            when sPrint =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '1';
              nextState <= sPrintC;

            when sPrintC =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '1';
              if OUT_BUSY = '1' then
                nextState <= sPrintC;
              else
                OUT_WE <= '1';
                OUT_DATA <= DATA_RDATA;
                pc_inc <= '1';
                nextState <= sFetch;
              end if;
            
            when sLoad =>
              IN_REQ <= '1';
              nextState <= sLoadC;
            
            when sLoadC =>
              IN_REQ <= '1';
              if IN_VLD = '1' then
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mxslc_1 <= '1';
                mxslc_2 <= "00";
                pc_inc <= '1';
                nextState <= sFetch;
              else
                nextState <= sLoadC;
              end if;
            
            when sWhile_init =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              pc_inc <= '1';
              mxslc_1 <= '1';
              nextState <= sWhile;
            
            when sWhile =>
              if DATA_RDATA = X"00" then
                -- skip
                cnt_inc <= '1';
                mxslc_1 <= '0';
                DATA_RDWR <= '0';
                DATA_EN <= '1';
                nextState <= sWhile2; 
              else
                nextState <= sFetch;
              end if;
            
            when sWhile2 =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '0';
              nextState <= sWhile3;
            
            when sWhile3 =>
            if cnt = "00000000" then
              pc_dec <= '1';
              nextState <= sFetch;
            else
              if DATA_RDATA = X"5B" then
                cnt_inc <= '1';
              elsif DATA_RDATA = X"5D" then
                cnt_dec <= '1'; 
              end if;
              pc_inc <= '1';
              nextState <= sWhile2;
            end if;
            
            when sWhile_end =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '1';
              nextState <= sWhile_end1;
            
            when sWhile_end1 =>
              if DATA_RDATA = X"00" then
                pc_inc <= '1';
                nextState <= sFetch;
              else
                -- go back to while start
                cnt_inc <= '1';
                pc_dec <= '1';
                nextState <= sWhile_end2;
              end if;
            
            when sWhile_end2 =>
              if cnt = "00000000" then
                nextState <= sFetch;
              else
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mxslc_1 <= '0';
                nextState <= sWhile_end3;
              end if;

            when sWhile_end3 =>
              if DATA_RDATA = X"5B" then
                nextState <= sFetch;
                cnt_dec <= '1';
                pc_inc <= '1';
              else
                pc_dec <= '1';
                nextState <= sWhile_end2;
              end if;
                
            when sDoWhile_init =>
              pc_inc <= '1';
              ptr_do_wh <= pc + 1;
              mxslc_1 <= '1';
              nextState <= sFetch;
            
            when sDoWhile_end =>
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mxslc_1 <= '1';
              nextState <= sDoWhile;

            when sDoWhile =>
              if DATA_RDATA = X"00" then
                pc_inc <= '1';
                nextState <= sFetch;
              else
                pc_jmp <= '1';
                nextState <= sFetch;
              end if;
            
            when sNull =>
              nextState <= sNull;
            
            when sOther =>
              pc_inc <= '1';
              nextState <= sFetch;
            
            when others =>
          end case;
  end process;
end behavioral;

