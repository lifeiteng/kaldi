#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import os
import logging
from optparse import OptionParser
from collections import defaultdict
import operator
import re

# reload(sys)
# sys.setdefaultencoding("utf-8")


usage = '%prog [options] '
parser = OptionParser(usage)
parser.add_option('--special-symbol', dest='special_symbol', default="***")
parser.add_option('--separator', dest='separator', default=";")
parser.add_option('--detail', dest='detail', default='True')
parser.add_option('--equal-pattern', dest='equal_pattern', default='')
parser.add_option('--ground-truth', dest='ground_truth', default='hyp')

(opt, argv) = parser.parse_args()

if len(argv) != 3:
    print parser.print_help()
    exit(-1)

detail = (opt.detail == 'True' or opt.detail == 'true')
hyp_ground_truth = (opt.ground_truth == 'hyp' or opt.ground_truth == 'HYP')

per_utt_file = argv[0]
ops_file = argv[1]
ref_hyp_file = argv[2]

extra_size = 4
max_size = 16

per_utt = dict()
per_utt['error'] = defaultdict(list)

def ecount():
    return {'count': 0, 'utts': []}

error_counts = defaultdict(ecount)


equal_pattern = set()
if opt.equal_pattern:
    with open(opt.equal_pattern) as f:
        for line in f:
            line = line.strip()
            if line.startswith('#'):
                continue
            m = re.match(r'.*((\(.+\))<-(\(.+\))).*', line)
            if m:
                # print m.group(1), m.group(2), m.group(3)
                equal_pattern.add(m.group(1))
                equal_pattern.add("(%s)<-(%s)" % (m.group(3), m.group(2)))
# print equal_pattern

ref_hyp_minwer = defaultdict(defaultdict)

with open(per_utt_file) as f:
    for line in f:
        # splits = line.strip().replace(opt.special_symbol, '').split()
        splits = line.strip().split()
        if not splits[1] in ['ref', 'hyp', 'op', "#csid"]:
            print "Error line"
            exit(-1)
        wav_key = splits[0]
        flag = splits[1]
        words = splits[2:]
        per_utt[flag] = words

        if flag == 'hyp':
            ref_words = per_utt['ref']
            hyp_words = per_utt['hyp']
            assert len(ref_words) == len(hyp_words)

            # 插入 <s> ... </s>
            ref_words.insert(0, '<s>')
            ref_words.append('</s>')

            hyp_words.insert(0, '<s>')
            hyp_words.append('</s>')

            minwer_ref_words = []
            minwer_hyp_words = []

            ref_tmp = []
            hyp_tmp = []
            ctx_left = '<s>'
            ctx_right = '</s>'
            # print "ref_words:", ref_words
            # print "hyp_words:", hyp_words
            for i in range(0, len(ref_words)):
                # print i, ref_words[i]
                if ref_words[i] == hyp_words[i]:
                    if len(ref_tmp) != 0 or len(hyp_tmp) != 0:
                        ctx_right = ref_words[i]
                        ref_text = ' '.join(ref_tmp).replace(opt.special_symbol, '').strip()
                        hyp_text = ' '.join(hyp_tmp).replace(opt.special_symbol, '').strip()
                        per_utt['error'][wav_key].append([ref_text, hyp_text, ctx_left, ctx_right])

                        ref_hyp_diff = '(%s)<-(%s)' % (ref_text, hyp_text)
                        if ref_hyp_diff not in equal_pattern:
                            error_counts[ref_hyp_diff]['count'] += 1
                            error_counts[ref_hyp_diff]['utts'].append(wav_key)
                            minwer_ref_words.extend(ref_tmp)
                            minwer_hyp_words.extend(hyp_tmp)
                        else:
                            # print "ref_hyp_diff are equal:", ref_hyp_diff
                            if hyp_ground_truth:
                                minwer_ref_words.extend(hyp_tmp)
                                minwer_hyp_words.extend(hyp_tmp)
                            else:
                                minwer_ref_words.extend(ref_tmp)
                                minwer_hyp_words.extend(ref_tmp)
                        ref_tmp = []
                        hyp_tmp = []
                        ctx_left = ref_words[i]
                    else:
                        ctx_left = ref_words[i]
                    minwer_ref_words.append(ref_words[i])
                    minwer_hyp_words.append(hyp_words[i])
                else:
                    ref_tmp.append(ref_words[i])
                    hyp_tmp.append(hyp_words[i])
            # ref_hyp_minwer[wav_key]['ref'] = ' '.join(minwer_ref_words[1:][:-1]).replace(opt.special_symbol, '')
            # ref_hyp_minwer[wav_key]['hyp'] = ' '.join(minwer_hyp_words[1:][:-1]).replace(opt.special_symbol, '')
            ref_hyp_minwer[wav_key]['ref'] = ' '.join(' '.join(minwer_ref_words[1:][:-1]).replace(opt.special_symbol, '').split())
            ref_hyp_minwer[wav_key]['hyp'] = ' '.join(' '.join(minwer_hyp_words[1:][:-1]).replace(opt.special_symbol, '').split())

with open(ops_file, 'w') as f:
    for wav_key in per_utt['error']:
        if per_utt['error'][wav_key]:
            print >>f, "-------\n%s" % (wav_key)
        for error in per_utt['error'][wav_key]:
            print >>f, "%16s %16s (%s)<-(%s)" % (error[2], error[3], error[0], error[1])
        print >>f, "-------\n"

with open(ops_file + ".count", 'w') as f:
    counts_error = defaultdict(list)
    for k in error_counts:
        counts_error[error_counts[k]['count']].append(k)

    for item in sorted(counts_error.items(), key=operator.itemgetter(0))[::-1]:
        print >>f, "-----\n count %10d" % (item[0])
        for error in sorted(item[1], key=lambda s: len(s)):
            print >>f, "%10d %s" % (item[0], error)

with open(ops_file + ".bigdiff", 'w') as f:
    for error in sorted(error_counts, key=lambda s: len(s))[::-1]:
        if detail:
            print >>f, error_counts[error]['count'], error, error_counts[error]['utts']
        else:
            print >>f, error_counts[error]['count'], error

with open(ref_hyp_file, 'w') as f:
    for wk in ref_hyp_minwer:
        print >>f, '%s ref %s' % (wk, ref_hyp_minwer[wk]['ref'])
        print >>f, '%s hyp %s' % (wk, ref_hyp_minwer[wk]['hyp'])

print "DONE!"

