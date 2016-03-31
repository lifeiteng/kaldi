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

def get_hash_str(val):
    return hashlib.md5(str(val)).hexdigest()

class MakeTrans:
    def __init__(self, postfix, in_flist, input_snr, out_txt, out_scp, utt2spk):
        self.SpknameDict = dict()
        self.TspDict = dict()

        self.F = open(input_snr, 'r').readlines()

        self.G = open(in_flist, 'r').readlines()
        self.postfix = postfix

        self.O = open(out_txt, 'w')
        self.P = open(out_scp, 'w')
        self.U = open(utt2spk, 'w')
        self.Fdict()

    def Fdict(self):
        for line in self.F:
            m = re.match(r'(.+) \((.+)\)$', line.strip())
            self.TspDict[m.group(2).strip()] = m.group(1).strip().lower()

    def ProcessAllInOne(self):
        no_tsp_num = 0
        utt2spk = dict()
        for i in range(0,self.G.__len__()):
            # 4584_engzo_2603_ios
            # 4294_engzo_1983_android
            # 4672_engzo_2577_android
            if not os.path.isfile(self.G[i].strip()):
                continue
            wavname = self.G[i].strip().split("/")[-1]
            sp = wavname.split("_")
            spkname = sp[0]

            if True:
                spkname = get_hash_str(spkname)
                assert spkname != ''
                if wavname.find('ios') > 0:
                    spkname = spkname
                else:
                    spkname = spkname
            else:
                continue

            if sp[1] != 'engzo' and not wechat:
                print self.G[i].strip(), " bad wav file name."
                continue

            uttname = sp[2]
            spkuttname = wavname[:-4]
            # print sp
            if len(sp[0]) == 0 or len(uttname)==0 or len(spkuttname) == 0:
                print self.G[i].strip(), " bad wav file name."
                continue

            if self.G[i].strip()[-4:] != ".wav":
                print self.G[i].strip(), " is not correct wav file name."
                continue

            if self.TspDict.has_key(spkuttname):
                key = spkname + '_' + spkuttname.replace('.', '_') + "_" + self.postfix
                if not utt2spk.has_key(spkname):
                    utt2spk[spkname] = []
                utt2spk[spkname].append(key)

                print >> self.O, "%s %s" %(key, self.TspDict[spkuttname])
                print >> self.P, "%s %s" %(key, self.G[i].strip())
            else:
                no_tsp_num += 1
                #print "%s no trans for sent utt: %s" %(self.postfix, spkuttname)

            if i % 100000 == 0 :
                print " make_trans.py has process %f" % (float(i)/self.G.__len__())
        for spkname in sorted(utt2spk.keys()):
            utts = utt2spk[spkname]
            assert len(utts) > 0
            for utt in utts:
                print >>self.U, '%s %s' % (utt, spkname)

        print "%s wavs have no transcriptions. percent %.3f" %(no_tsp_num, no_tsp_num*100.0/self.G.__len__())

        self.O.close()
        self.P.close()
        self.U.close()


if __name__ == "__main__":

    if len(sys.argv) == 8:
        wechat = (sys.argv[7] == 'True')
    print "Wechat =", wechat

    MakeTrans(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6])
    print " Done. "


