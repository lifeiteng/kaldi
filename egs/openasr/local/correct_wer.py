#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import os
import logging
from optparse import OptionParser

from werpp import lev_changes_naive

# reload(sys)
# sys.setdefaultencoding("utf-8")


class CorrectedWER(object):
    def __init__(self):
        pass

    def _load_key_value(self, kv_file):
        kv = dict()
        with open(kv_file) as f:
            for line in f:
                splits = line.strip().split()
                if len(splits) <= 1:
                    continue
                else:
                    kv[splits[0]] = ' '.join(splits[1:])
        return kv

    def WER(self, refs_file='', hyps_file=''):
        refs = self._load_key_value(refs_file)
        hyps = self._load_key_value(hyps_file)
        ins_all = 0
        dels_all = 0
        subs_all = 0

        ref_count = 0

        not_in_refs = 0
        sent_error = 0
        sent_num = 0
        for k in hyps:
            if k not in refs:
                not_in_refs += 1
                continue
            sent_num += 1
            w_ref = refs[k].split()
            w_hyp = hyps[k].split()

            ref_count += len(w_ref)

            ins_naive, del_naive, subs_naive = lev_changes_naive(w_hyp, w_ref)
            if (ins_naive + del_naive + subs_all) != 0:
                sent_error += 1

            ins_all += ins_naive
            dels_all += del_naive
            subs_all += subs_naive
        # %WER 32.90 [ 89552 / 272210, 20828 ins, 15173 del, 53551 sub ] exp/nnet3/lstm_bidirectional_ld0/decode_telis/wer_18_0.0
        ref_count = max(1, ref_count)
        sent_num = max(1, sent_num)
        all_diff = subs_all + ins_all + dels_all
        print "%sWER %.2f [ %d / %d, %d ins, %d del, %d sub ]" % ('%', float(all_diff)/ref_count*100, all_diff, ref_count, ins_all, dels_all, subs_all)
        print "%sSER %.2f [ %d / %d ]" % ("%", 100.0 * sent_error / sent_num, sent_error, sent_error)
        print not_in_refs, " not in refs."


if __name__ == '__main__':
    usage = '%prog [options] '
    parser = OptionParser(usage)
    parser.add_option('--xxoo', dest='xxoo', default=False)
    (opt, argv) = parser.parse_args()

    if len(argv) != 2:
        print parser.print_help()
        exit(-1)
    wer = CorrectedWER()
    wer.WER(refs_file=argv[0], hyps_file=argv[1])
