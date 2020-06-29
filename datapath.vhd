library IEEE;
use IEEE.Std_Logic_1164.all;
use IEEE.Std_Logic_signed.all; -- needed for comparison instructions SLTx
use IEEE.Std_Logic_arith.all; -- needed for comparison instructions SLTxU
use work.p_MIPS_MCS.all;
   
entity datapath is
      port(  ck, rst :     in std_logic;
             d_address :   out std_logic_vector(31 downto 0);
             data :        inout std_logic_vector(31 downto 0); 
				 inst_branch_out, salta_out : out std_logic;
             end_mul :	   out std_logic;
             end_div :	   out std_logic;
             RESULT_OUT :  out std_logic_vector(31 downto 0);
             uins :        in microinstruction;
             IR_IN :  		in std_logic_vector(31 downto 0);
				 NPC_IN : 		in std_logic_vector(31 downto 0)
          );
end datapath;

architecture datapath of  datapath is
    signal result, R1, R2, R3, R1_in, R2_in, R3_in, RIN, sign_extend, op1, op2, 
           outalu, RALU, MDR, mdr_int, HI, LO,
			  quociente, resto, D_Hi, D_Lo : std_logic_vector(31 downto 0) := (others=> '0');
    signal adD, adS : std_logic_vector(4 downto 0) := (others=> '0');    
    signal inst_branch, inst_R_sub, inst_I_sub, rst_muldiv: std_logic;   
    signal salta : std_logic := '0';
    signal produto : std_logic_vector(63 downto 0);
begin

   -- auxiliary signals 
   inst_branch  <= '1' when uins.i=BEQ or uins.i=BGEZ or uins.i=BLEZ or uins.i=BNE or uins.i=BGEZAL else 
                  '0';
	inst_branch_out <= inst_branch;
   
	-- inst_R_sub is a subset of R-type instructions
   inst_R_sub  <= '1' when uins.i=ADDU or uins.i=SUBU or uins.i=AAND
                         or uins.i=OOR or uins.i=XXOR or uins.i=NNOR else
                   '0';

	-- inst_I is a subset of I-type instructions
   inst_I_sub  <= '1' when uins.i=ADDIU or uins.i=ANDI or uins.i=ORI or uins.i=XORI else
                   '0';

   --==============================================================================
   -- second stage
   --==============================================================================
                
   -- The then clause is only used for logic shifts with a shamt field       
   M3: adS <= IR_IN(20 downto 16) when uins.i=SSLL or uins.i=SSRA or uins.i=SSRL else 
          IR_IN(25 downto 21);
          
   REGS: entity work.reg_bank(reg_bank) port map
        (AdRP1=>adS, DataRP1=>R1_in, AdRP2=>IR_IN(20 downto 16), DataRP2=>R2_in,
		   ck=>ck, rst=>rst, ce=>uins.wreg, AdWP=>adD, DataWP=>RIN);
    
   -- sign extension 
   sign_extend <=  x"FFFF" & IR_IN(15 downto 0) when IR_IN(15)='1' else
             x"0000" & IR_IN(15 downto 0);
    
   -- Immediate constant
   M5: R3_in <= sign_extend(29 downto 0)  & "00"     when inst_branch='1'			else
                -- branch address adjustment for word frontier
             "0000" & IR_IN(25 downto 0) & "00" when uins.i=J or uins.i=JAL 		else
                -- J/JAL are word addressed. MSB four bits are defined at the ALU, not here!
             x"0000" & IR_IN(15 downto 0) when uins.i=ANDI or uins.i=ORI  or uins.i=XORI 	else
                -- logic instructions with immediate operand are zero extended
             sign_extend;
                -- The default case is used by addiu, lbu, lw, sbu and sw instructions
             
   -- second stage registers
   R1reg:  entity work.regnbits port map(ck=>ck, rst=>rst, ce=>uins.CY2, D=>R1_in, Q=>R1);

   R2reg:  entity work.regnbits port map(ck=>ck, rst=>rst, ce=>uins.CY2, D=>R2_in, Q=>R2);
  
   R3reg: entity work.regnbits port map(ck=>ck, rst=>rst, ce=>uins.CY2, D=>R3_in, Q=>R3);
 
 
  --==============================================================================
   -- third stage
   --==============================================================================
                      
   -- select the first ALU operand
   M6: op1 <= 	NPC_IN  when (inst_branch='1' or uins.i=J or uins.i=JAL) else R1; 
     
   -- select the second ALU operand
   M7: op2 <= 	R2 when inst_R_sub='1' or uins.i=SLTU or uins.i=SLT or uins.i=JR 
                  or uins.i=SLLV or uins.i=SRAV or uins.i=SRLV else 
          	R3; 
                 
   -- ALU instantiation
   DALU: entity work.alu port map (op1=>op1, op2=>op2, outalu=>outalu, op_alu=>uins.i);
   
   -- ALU register
   Reg_ALU: entity work.regnbits  port map(ck=>ck, rst=>rst, ce=>uins.walu, 
				D=>outalu, Q=>RALU);               
 
   -- evaluation of conditions to take the branch instructions
   salta <=  '1' when ( (R1=R2  and uins.i=BEQ)  or (R1>=0  and (uins.i=BGEZ or uins.i=BGEZAL)) or
                        (R1<=0  and uins.i=BLEZ) or (R1/=R2 and uins.i=BNE) ) else
             '0';
   salta_out <= salta;
	
	-- Reset do multiplicador e divisor
	rst_muldiv <= rst or uins.rst_md; 
	
	-- multiplier and divider instantiations
   inst_mult: entity work.multiplica                   
      port map (Mcando=>R1_in, Mcador=>R2_in, clock=>ck,
	  start=>rst_muldiv, endop=>end_mul, produto=>produto);
	  
   inst_div: entity work.divide                  
      generic map (32)
      port map (dividendo=>R1_in, divisor=>R2_in, clock=>ck,
	  start=>rst_muldiv, endop=>end_div, quociente=>quociente, resto=>resto);

   D_Hi <= produto(63 downto 32) when uins.i=MULTU else 
          resto; 
   D_Lo <= produto(31 downto 0) when uins.i=MULTU else 
          quociente; 

      -- HI and LO registers
   REG_HI: entity work.regnbits  port map(ck=>ck, rst=>rst, ce=>uins.whilo, 
			D=>D_Hi, Q=>HI);               
   REG_LO: entity work.regnbits  port map(ck=>ck, rst=>rst, ce=>uins.whilo, 
			D=>D_Lo, Q=>LO);               

   --==============================================================================
   -- fourth stage
   --==============================================================================
     
   d_address <= RALU;
    
   -- tristate to control memory write    
   data <= R2 when (uins.ce='1' and uins.rw='0') else (others=>'Z');  

   -- single byte reading from memory  -- assuming the processor is little endian
   M8: mdr_int <= data when uins.i=LW  else
              x"000000" & data(7 downto 0);
       
   RMDR: entity work.regnbits  port map(ck=>ck, rst=>rst, ce=>uins.wmdr,
			D=>mdr_int, Q=>MDR);                 
  
   M9: result <=	MDR when uins.i=LW  or uins.i=LBU else
	   		HI when uins.i=MFHI else
	   		LO when uins.i=MFLO else
                	RALU;

   --==============================================================================
   -- fifth stage
   --==============================================================================

   -- signal to be written into the register bank
   M2: RIN <= NPC_IN when (uins.i=JALR or uins.i=JAL or (uins.i=BGEZAL and salta='1')) else result;
   
   -- register bank write address selection
   M4: adD <= "11111"           when uins.i=JAL or (uins.i=BGEZAL and salta='1') else -- JAL and BGEZAL writes in register $31
         IR_IN(15 downto 11)    when (inst_R_sub='1' 
					or uins.i=SLTU or uins.i=SLT
					or uins.i=JALR
					or uins.i=MFHI or uins.i=MFLO
					or uins.i=SSLL or uins.i=SLLV
					or uins.i=SSRA or uins.i=SRAV
					or uins.i=SSRL or uins.i=SRLV) else
         IR_IN(20 downto 16) 	-- inst_I_sub='1' or uins.i=SLTIU or uins.i=SLTI 
        ;                 		-- or uins.i=LW or  uins.i=LBU  or uins.i=LUI, or default
    
  RESULT_OUT <= result;
	 
end datapath;