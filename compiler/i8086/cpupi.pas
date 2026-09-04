{
    Copyright (c) 2002 by Florian Klaempfl

    This unit contains the CPU specific part of tprocinfo

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}

{ This unit contains the CPU specific part of tprocinfo. }
unit cpupi;

{$i fpcdefs.inc}

  interface

    uses
       psub,procinfo,aasmdata;

    type
       tcpuprocinfo = class(tcgprocinfo)
       private
         { set by calc_stackframe_size when a procedure that omitted its frame
           turned out to need temps after all, see there }
         frame_restored : boolean;
         procedure insert_8087_fwaits(list : TAsmList);
         procedure restore_frame_references(list : TAsmList);
         procedure restore_frame_localloc(p : TObject; arg : pointer);
         procedure check_no_stack_references(list : TAsmList);
         procedure record_used_int_regs;
       public
         constructor create(aparent:tprocinfo);override;
         procedure set_first_temp_offset;override;
         function calc_stackframe_size:longint;override;
         procedure generate_parameter_info;override;
         procedure postprocess_code;override;
       end;


  implementation

    uses
      cutils,verbose,
      systems,globals,globtype,
      aasmtai,aasmcpu,
      cgobj,tgobj,paramgr,
      cpubase,cpuinfo,
      cgutils,
      symconst,symtype,symsym,cgbase;

    constructor tcpuprocinfo.create(aparent:tprocinfo);
      begin
        inherited create(aparent);
        got:=NR_EBX;
      end;


    procedure tcpuprocinfo.set_first_temp_offset;
      begin
        if paramanager.use_fixed_stack then
          begin
            if not(po_assembler in procdef.procoptions) and
               (tg.direction > 0) then
              tg.setfirsttemp(tg.direction*maxpushedparasize);
            if (tg.direction < 0) and
               not(po_nostackframe in procdef.procoptions) then
              { compensate for the return address and the "pushl %ebp" }
              tg.setalignmentmismatch(sizeof(pint)*2);
          end;
      end;


    function tcpuprocinfo.calc_stackframe_size:longint;
      begin
        { ???:
          align to 4 bytes at least
          otherwise all those subl $2,%esp are meaningless PM }
        if target_info.stackalign<=2 then
          result:=Align(tg.direction*tg.lasttemp,min(current_settings.alignment.localalignmax,2))
        else
          { aligned during stack frame allocation, because also depends number
            of saved registers }
          result:=tg.direction*tg.lasttemp+maxpushedparasize;

        { A procedure that omitted its frame (tcgprocinfo.setup_tempgen) may
          still have ended up with temps: spilled registers, locals that could
          not stay in a register, temps of expressions.  i8086 cannot address
          memory relative to sp, and a bp frame (4 bytes) is cheaper than a
          "mov reg,sp" in front of every access, so the frame is put back.
          This is called right before the entry code is generated, which is
          the last moment the frame pointer can change; the sp based
          references already emitted are rewritten to bp by postprocess_code,
          once the entry code has fixed the distance between sp and bp. }
        if (result<>0) and
           (framepointer=NR_STACK_POINTER_REG) and
           (pi_no_framepointer_needed in flags) then
          begin
            framepointer:=NR_FRAME_POINTER_REG;
            exclude(flags,pi_no_framepointer_needed);
            frame_restored:=true;
          end;
      end;


    procedure tcpuprocinfo.restore_frame_localloc(p : TObject; arg : pointer);
      begin
        if (tsym(p).typ in [paravarsym,localvarsym]) and
           (tabstractnormalvarsym(p).localloc.loc in [LOC_REFERENCE,LOC_CREFERENCE]) and
           (tabstractnormalvarsym(p).localloc.reference.base=NR_STACK_POINTER_REG) then
          with tabstractnormalvarsym(p).localloc.reference do
            begin
              base:=NR_FRAME_POINTER_REG;
              inc(offset,plongint(arg)^);
              if segment=NR_SS then
                segment:=NR_NO;
            end;
      end;


    procedure tcpuprocinfo.restore_frame_references(list : TAsmList);
      var
        delta : longint;
        curtai : tai;
        i : longint;
      begin
        { g_proc_entry set save_regs_ref to the bottom of the frame, below the
          locals and the pushed registers; that is where sp stays for the whole
          body, so sp = bp + save_regs_ref.offset }
        if save_regs_ref.base<>NR_FRAME_POINTER_REG then
          internalerror(2026090401);
        delta:=save_regs_ref.offset;
        curtai:=tai(list.First);
        while assigned(curtai) do
          begin
            if curtai.typ=ait_instruction then
              for i:=0 to taicpu(curtai).ops-1 do
                if taicpu(curtai).oper[i]^.typ=top_ref then
                  with taicpu(curtai).oper[i]^.ref^ do
                    begin
                      if index=NR_STACK_POINTER_REG then
                        internalerror(2026090402);
                      if base=NR_STACK_POINTER_REG then
                        begin
                          base:=NR_FRAME_POINTER_REG;
                          inc(offset,delta);
                          { bp addresses the stack segment by default }
                          if segment=NR_SS then
                            segment:=NR_NO;
                        end;
                    end;
            curtai:=tai(curtai.Next);
          end;
        { the locations the debug info will describe }
        procdef.parast.SymList.ForEachCall(@restore_frame_localloc,@delta);
        procdef.localst.SymList.ForEachCall(@restore_frame_localloc,@delta);
      end;


    procedure tcpuprocinfo.check_no_stack_references(list : TAsmList);
      var
        curtai : tai;
        i : longint;
      begin
        { without temps nothing may address memory through sp: such a
          reference would have to come from a path setup_tempgen did not
          exclude, and it cannot be encoded }
        curtai:=tai(list.First);
        while assigned(curtai) do
          begin
            if curtai.typ=ait_instruction then
              for i:=0 to taicpu(curtai).ops-1 do
                if (taicpu(curtai).oper[i]^.typ=top_ref) and
                   ((taicpu(curtai).oper[i]^.ref^.base=NR_STACK_POINTER_REG) or
                    (taicpu(curtai).oper[i]^.ref^.index=NR_STACK_POINTER_REG)) then
                  internalerror(2026090403);
            curtai:=tai(curtai.Next);
          end;
      end;


    procedure tcpuprocinfo.generate_parameter_info;
      begin
        inherited generate_parameter_info;
        { Para_stack_size is only used to determine how many bytes to remove }
        { from the stack at the end of the procedure (in the "ret $xx").     }
        { If the stack is fixed, nothing has to be removed by the callee     }
        if paramanager.use_fixed_stack then
          para_stack_size := 0;
      end;


    procedure tcpuprocinfo.insert_8087_fwaits(list : TAsmList);
      var
        curtai: tai;
      begin
        curtai:=tai(list.First);
        while assigned(curtai) do
          begin
            if (curtai.typ=ait_instruction)
               and requires_fwait_on_8087(taicpu(curtai).opcode) then
              list.InsertBefore(taicpu.op_none(A_FWAIT),curtai);

            curtai:=tai(curtai.Next);
          end;
      end;


    procedure tcpuprocinfo.record_used_int_regs;
      { Tell the procdef which integer registers the finished code touches,
        so that callers compiled later in this unit protect only those
        across the call instead of the whole volatile set of the convention
        (tcgcallnode.pass_generate_code). The register allocator's
        used_in_proc has what it saw, including the volatile set assumed
        around every call in the body; the scan adds what appeared after it
        ran: prologue and epilogue, and registers the peephole optimizer
        picked itself (GetIntRegisterBetween takes a free volatile register
        without telling the allocator). Reads count as well: cheap, and the
        set is only compared with the volatile registers anyway. }
      var
        p : tai;
        regs : tcpuregisterset;
        ch : set of TInsChange;
        i,r : longint;
      begin
        if (po_assembler in procdef.procoptions) or
           (pi_is_assembler in flags) or
           (pi_has_assembler_block in flags) then
          exit;
        regs:=cg.rg[R_INTREGISTER].used_in_proc;
        p:=tai(aktproccode.first);
        while assigned(p) do
          begin
            case p.typ of
              ait_regalloc:
                if (tai_regalloc(p).ratype=ra_alloc) and
                   (getregtype(tai_regalloc(p).reg)=R_INTREGISTER) then
                  include(regs,getsupreg(tai_regalloc(p).reg));
              ait_instruction:
                begin
                  for i:=0 to taicpu(p).ops-1 do
                    case taicpu(p).oper[i]^.typ of
                      top_reg:
                        if getregtype(taicpu(p).oper[i]^.reg)=R_INTREGISTER then
                          include(regs,getsupreg(taicpu(p).oper[i]^.reg));
                      top_ref:
                        begin
                          if getregtype(taicpu(p).oper[i]^.ref^.base)=R_INTREGISTER then
                            include(regs,getsupreg(taicpu(p).oper[i]^.ref^.base));
                          if getregtype(taicpu(p).oper[i]^.ref^.index)=R_INTREGISTER then
                            include(regs,getsupreg(taicpu(p).oper[i]^.ref^.index));
                        end;
                      else
                        ;
                    end;
                  ch:=insprop[taicpu(p).opcode].Ch;
                  { a call's clobbers are the regalloc marks around it and a
                    return changes nothing, yet both carry Ch_All; anything
                    else with it (int, into, cmpxchg) is not generated from
                    Pascal, so just give up on such a body }
                  if Ch_All in ch then
                    case taicpu(p).opcode of
                      A_CALL,A_RET,A_RETN,A_RETF,A_RETW,A_RETNW,A_RETFW:
                        ;
                      else
                        exit;
                    end;
                  { Ch_R/W/RW/M groups are ordered like the superregisters:
                    ax cx dx bx sp bp si di }
                  for r:=0 to 7 do
                    if [TInsChange(ord(Ch_REAX)+r),TInsChange(ord(Ch_WEAX)+r),
                        TInsChange(ord(Ch_RWEAX)+r),TInsChange(ord(Ch_MEAX)+r)]*ch<>[] then
                      include(regs,r);
                end;
              else
                ;
            end;
            p:=tai(p.next);
          end;
        procdef.used_int_regs:=regs;
        procdef.used_int_regs_known:=true;
      end;


    procedure tcpuprocinfo.postprocess_code;
      begin
        if frame_restored then
          restore_frame_references(aktproccode)
        else if (framepointer=NR_STACK_POINTER_REG) and
                (pi_no_framepointer_needed in flags) then
          check_no_stack_references(aktproccode);
        { nickysn note: I don't know if the 187 requires FWAIT before
          every instruction like the 8087, so I'm including it just in case }
        if current_settings.cputype<=cpu_186 then
          insert_8087_fwaits(aktproccode);
        { the code is final now }
        record_used_int_regs;
      end;

begin
   cprocinfo:=tcpuprocinfo;
end.
