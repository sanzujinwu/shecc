/*
 * shecc - Self-Hosting and Educational C Compiler.
 *
 * shecc is freely redistributable under the BSD 2 clause license. See the
 * file "LICENSE" for information on usage and redistribution of this file.
 */

int is_fusible_insn(ph2_ir_t *ph2_ir)
{
    switch (ph2_ir->op) {
    case OP_add:
    case OP_sub:
    case OP_mul:
    case OP_div:
    case OP_mod:
    case OP_lshift:
    case OP_rshift:
    case OP_bit_and:
    case OP_bit_or:
    case OP_bit_xor:
    case OP_log_and:
    case OP_log_or:
    case OP_log_not:
    case OP_negate:
    case OP_load:
    case OP_global_load:
    case OP_load_data_address:
        return 1;
    default:
        return 0;
    }
}

void insn_fusion(ph2_ir_t *ph2_ir)
{
    ph2_ir_t *next = ph2_ir->next;
    if (!next)
        return;

    if (next->op == OP_assign) {
        /* eliminate {ALU rn, rs1, rs2; mv rd, rn;} */
        if (!is_fusible_insn(ph2_ir))
            return;
        if (ph2_ir->dest == next->src0) {
            ph2_ir->dest = next->dest;
            ph2_ir->next = next->next;
            return;
        }
    }
    /* other insn fusions */
}

/* FIXME: release detached basic blocks */
void peephole()
{
    fn_t *fn;
    for (fn = FUNC_LIST.head; fn; fn = fn->next) {
        basic_block_t *bb;
        for (bb = fn->bbs; bb; bb = bb->rpo_next) {
            ph2_ir_t *ph2_ir;
            for (ph2_ir = bb->ph2_ir_list.head; ph2_ir; ph2_ir = ph2_ir->next) {
                ph2_ir_t *next = ph2_ir->next;
                if (!next)
                    continue;
                if (next->op == OP_assign && next->dest == next->src0) {
                    ph2_ir->next = next->next;
                    continue;
                }
                insn_fusion(ph2_ir);
            }
        }
    }
}
