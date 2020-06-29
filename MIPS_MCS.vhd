library IEEE;
use IEEE.Std_Logic_1164.all;
use work.p_MIPS_MCS.all;

entity MIPS_MCS is
    port( clock, reset: in std_logic;
          ce, rw, bw: out std_logic;
          i_address, d_address: out std_logic_vector(31 downto 0);
          instruction: in std_logic_vector(31 downto 0);
          data: inout std_logic_vector(31 downto 0));
end MIPS_MCS;

architecture MIPS_MCS of MIPS_MCS is
      signal IR, NPC, RESULT: std_logic_vector(31 downto 0);
      signal uins: microinstruction;  
	  signal inst_branch, salta, end_mul, end_div: std_logic;
 begin

     dp: entity work.datapath   
         port map(ck=>clock, rst=>reset, d_address=>d_address, data=>data,
		  inst_branch_out=>inst_branch, salta_out=>salta,
		  end_mul=>end_mul, end_div=>end_div, RESULT_OUT=>RESULT,
		  uins=>uins, IR_IN=>IR, NPC_IN=>NPC);

     ct: entity work.control_unit port map( ck=>clock, rst=>reset, 
		i_address=>i_address, instruction=>instruction,
		inst_branch_in=>inst_branch, salta_in=>salta, 
		end_mul=>end_mul, end_div=>end_div, RESULT_IN=>RESULT,
		uins=>uins, IR_OUT=>IR, NPC_OUT=>NPC);
         
     ce <= uins.ce;
     rw <= uins.rw; 
     bw <= uins.bw;
     
end MIPS_MCS;