#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import os
from optparse import OptionParser
import re
import pandas as pd
from collections import defaultdict
import random

import matplotlib as mpl
mpl.use('Agg')
from matplotlib import pyplot as plt
import seaborn as sns
sns.set(color_codes=True)

# %WER 15.41 [ 3777 / 24517, 560 ins, 449 del, 2768 sub ] exp/chainnoise/tdnn_sp_clean_online/decode_final_clean/wer_13_0.0
# %WER 16.62 [ 4074 / 24517, 601 ins, 436 del, 3037 sub ] exp/chainnoise/tdnn_sp_snr10_nois_home_hour500_online/decode_final_clean/wer_13_0.0
# %WER 15.78 [ 3869 / 24517, 535 ins, 430 del, 2904 sub ] exp/chainnoise/tdnn_sp_snr10_nois_home_hour500_online/decode_final_snr25-noise-home/wer_13_0.0

def ParseWERFile(wer_file):
    parse_regex = re.compile(
        "%WER (.*) \[.*\] exp/.*/tdnn_sp_(.*)_online/decode_(.*)/wer.*")
    mixed_wers = defaultdict(lambda: {})
    subset_wers = defaultdict(lambda: {})
    with open(wer_file) as f:
        for line in f:
            line = line.strip().replace('[PARTIAL] ', '')
            mat_obj = parse_regex.search(line)
            if mat_obj is not None:
                groups = mat_obj.groups()
                # print line.strip()
                # print groups
                groups_2 = groups[2].replace('final_', '').replace('noise-', '').replace('785_', '')
                if groups[2].find('mixed') < 0 and groups[2].find('clean') < 0:
                    subset_wers[groups[1].replace('nois_', '')][groups_2] = float(groups[0])
                elif groups[1].find('clean') >= 0 or groups[1].find('accan') >= 0 or groups[2].find('mixed') >= 0:
                    # if groups[2].find('mixed') >= 0:
                    #     print groups[2]
                    mixed_wers[groups[1].replace('nois_', '')][groups_2] = float(groups[0])
            else:
                print "Fail Parse WER line:", line.strip()
    return mixed_wers, subset_wers


def DecodeDirCmp(dir1, dir2):
    m1 = re.match(r'snr(-{0,1}\d+).*', dir1)
    m2 = re.match(r'snr(-{0,1}\d+).*', dir2)
    snr1 = None
    snr2 = None
    if m1:
        snr1 = m1.group(1)
    if m2:
        snr2 = m2.group(1)
    # print m1, m2
    if snr1 is None:
        return 1
    if snr2 is None:
        return -1
    # print "snr1=%s, snr2=%s" % (snr1, snr2)
    if float(snr1) < float(snr2):
        return -1
    else:
        return 1


def PlotWER(wers, figname):
    plt.figure(figsize=[12, 8])

    df = pd.DataFrame(wers)
    df = pd.DataFrame(df, index=sorted(df.index.tolist(), cmp=DecodeDirCmp),
                      columns=sorted(df.keys(), cmp=DecodeDirCmp))

    (rows, cols) = df.shape
    colorp = sns.color_palette("hls", cols)
    filled_markers = ['o', 'v', '^', '<', '>', '8', 's', 'p', '*', 'h', 'H',
                      'D', 'd']
    used_types = set()
    for c in range(cols):
        if c >= min(len(colorp), len(filled_markers)):
            cl = random.choice(range(cols))
            fm = random.choice(range(cols))
            while (cl, fm) in used_types:
                cl = random.choice(range(cols))
                fm = random.choice(range(cols))
            used_types.add((cl, fm))
            color = colorp[cl]
            marker = filled_markers[fm]
            print "random choice color=%s, marker=%s" % (color, marker)
        else:
            color = colorp[c]
            marker = filled_markers[c]
            used_types.add((c, c))
        plt.plot(range(rows), df.values[:, c], color=color, label=df.keys()[c], marker=marker,
            linewidth=2.9, linestyle=["-", "--", '-.', ':'][c % 4])

    plt.xlim([-1, rows])
    # print [n.replace('snr', '') for n in df.index.tolist()]
    plt.xticks(range(rows), [n.replace('snr', '') for n in df.index.tolist()])
    plt.legend()
    plt.xlabel('SNR')
    plt.ylabel('WER')
    # plt.show()
    plt.savefig(figname)


def AnalysisWER(wer_file, todir):
    mixed_wers, subset_wers = ParseWERFile(wer_file)
    if not os.path.isdir(todir):
        os.mkdir(todir)
    PlotWER(mixed_wers, os.path.join(todir, 'mixed-wer.png'))
    PlotWER(subset_wers, os.path.join(todir, 'subset-wer.png'))

if __name__ == '__main__':
    usage = '%prog wer-file to-dir'
    parser = OptionParser(usage)
    parser.add_option('--figlm', dest='figlm', default=4)
    parser.add_option('-E',
                      '--engzo',
                      action='store_true',
                      dest='E',
                      default=False)
    (opt, argv) = parser.parse_args()
    if len(argv) != 2:
        print parser.print_help()
        exit(-1)

    AnalysisWER(argv[0], argv[1])

    exit(0)
