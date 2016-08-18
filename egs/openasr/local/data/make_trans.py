#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'feiteng'
# -*- coding: utf-8 -*-
import re
import sys
import random
import string
import os
import hashlib
from optparse import OptionParser

corpus_types = ['openasr', 'voxpop', 'ted']
corpus_type = 'openasr'


def get_hash_str(val):
    return hashlib.md5(str(val)).hexdigest()


def GetKeyValue(line):
    splits = line.strip().split()
    assert len(splits) >= 2
    return (splits[0], ' '.join(splits[1:]))


def FixTrans(in_trans_file, out_trans_file):
    in_trans_lines = open(in_trans_file).readlines()
    try:
        with open(out_trans_file, 'w') as f:
            for line in in_trans_lines:
                m = re.match(r'(.+) \((.+)\)$', line.strip())
                if m is None:
                    (key, value) = GetKeyValue(line)
                    wav_name = key
                    trans_text = value.lower()
                else:
                    wav_name = m.group(2).strip()
                    trans_text = m.group(1).strip().lower()
                if not wav_name.endswith('.wav'):
                    wav_name = wav_name + '.wav'
                print >>f, wav_name, trans_text
    except:
        with open(in_trans_file, 'w') as f:
            for line in in_trans_lines:
                print >>f, line.strip()
        print "Except occur!!!"
        exit(-1)


class MakeTrans:
    def __init__(self, postfix, in_flist, input_snr, out_txt, out_scp, utt2spk, user_filter=''):
        self.SpknameDict = dict()
        self.trans = dict()

        self.wavlist = open(in_flist, 'r').readlines()
        self.postfix = postfix

        self.text = open(out_txt, 'w')
        self.wavscp = open(out_scp, 'w')
        self.utt2spk = open(utt2spk, 'w')
        self.user_filter = set()
        if user_filter != ''  and os.path.isfile(user_filter):
            with open(user_filter, 'r') as f:
                for line in f:
                    self.user_filter.add(line.strip())

        self.ParseTrans(input_snr)
        self.ProcessAllInOne()

    def ParseTrans(self, input_snr):
        input_snr_lines = open(input_snr, 'r').readlines()
        for line in input_snr_lines:
            (key, value) = GetKeyValue(line)
            self.trans[key] = value

    def GetWavName(self, line):
        return line.strip().split('/')[-1]

    def ProcessAllInOne(self):
        no_tsp_num = 0
        utt2spk = dict()
        for i in range(0, self.wavlist.__len__()):
            line = self.wavlist[i].strip()
            # 4584_engzo_2603_ios
            # 4294_engzo_1983_android
            # 4672_engzo_2577_android
            if not os.path.isfile(line):
                continue
            if not line.endswith('.wav'):
                continue

            wavname = self.GetWavName(line)
            sp = wavname.split("_")
            spkname = sp[0]
            if spkname in self.user_filter:  # filter test sets
                print "Skip speaker:", spkname
                continue

            key = wavname.replace('.wav', '') # 音频文件名
            if corpus_type == 'voxpop': # voxpop key修改为固定长度的hash string
                spkname = get_hash_str(spkname)
                key = '_'.join([spkname, get_hash_str(wavname)])
            assert spkname != ''
            key = key + '_' + self.postfix

            if self.trans.has_key(wavname):
                wav_file = self.wavlist[i].strip()
                sz = os.path.getsize(wav_file)
                if sz <= 100:
                    print "Too Small Filesize:", sz, wav_file
                    continue
                if not utt2spk.has_key(spkname):
                    utt2spk[spkname] = []
                utt2spk[spkname].append(key)

                print >> self.text, "%s %s" %(key, self.trans[wavname])
                print >> self.wavscp, "%s %s" %(key, wav_file)
            else:
                no_tsp_num += 1
                print "WARNING: No trans for utt: %s" %(wavname)

            if i % 10000 == 0 :
                print " make_trans.py has process %.3f" % (float(i)/self.wavlist.__len__())
        for spkname in sorted(utt2spk.keys()):
            utts = utt2spk[spkname]
            assert len(utts) > 0
            for utt in utts:
                print >>self.utt2spk, '%s %s' % (utt, spkname)

        print "%s wavs have no transcriptions. percent %.3f" %(no_tsp_num, no_tsp_num*100.0/self.wavlist.__len__())

        self.text.close()
        self.wavscp.close()
        self.utt2spk.close()


if __name__ == "__main__":
    usage = '%prog [options] postfix in_flist input_snr out_txt out_scp utt2spk '
    parser = OptionParser(usage)
    parser.add_option('--fix-trans', dest='fix_trans', default=False)
    parser.add_option('--corpus', dest='corpus', default='')
    parser.add_option('--user-filter', dest='user_filter', default='')
    (opt, argv) = parser.parse_args()

    if opt.fix_trans == 'True':
        assert len(argv) == 2
        FixTrans(argv[0], argv[1])
    else:
        if len(argv) != 6:
            print parser.print_help()
            exit(-1)
        assert opt.corpus
        corpus_type = opt.corpus
        if corpus_type not in corpus_types:
            print "Error corpus type, must be one of", corpus_types
            exit(-1)
        MakeTrans(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], user_filter=opt.user_filter)
    print __file__, " Done. "


