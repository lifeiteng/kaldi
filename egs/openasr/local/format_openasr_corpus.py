#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import os
import logging
import threading

from optparse import OptionParser

# 439532__150509__YjEwMWQwMDAwMGYzOTJjNA==__-1__54251c45636d734cc9837700_52ccc52bfcfff2bc45000c78.m4a.pb.raw
# reversed_time/date/user_id/transaction_id/activity_id_sentence_id.format.pb

def parse_raw_line(line):
    splits = line.strip().split('/')[-1].replace('.flac.pb.raw', '').replace(".m4a.pb.raw", "").split('__')
    # print splits
    if len(splits) != 5:
        print "Error line:", line
        return (None, None)
    (reversed_time, date, speaker, transaction_id, as_id) = splits
    speaker = speaker.replace('==', 'FT')
    if len(as_id) < 10:
        print "Error line:", line
        return (None, None)        

    (activity_id, sentence_id) = as_id.split('_')
    new_wav_file = '_'.join([speaker, activity_id, sentence_id, date]) + '.wav'
    return (speaker, new_wav_file)

def parse_trans_line(line):
    splits = line.strip().split()
    assert len(splits) >= 2
    (speaker, new_wav_file) = parse_raw_line(splits[0])
    if not speaker:
        return (None, None)
    transcription = ' '.join(splits[1:])
    # print "Transcription:", transcription
    return (new_wav_file, transcription)


def gen_ffmpeg_command(raw_name, new_wav_name, todir):
    ft = "-ac 1 -ar 16000 -f s16le"
    cmd = ["ffmpeg -y -loglevel panic", ft, "-i", raw_name,
           ft, todir + '/' + new_wav_name + ' </dev/null']
    return ' '.join(cmd)


def run(raws_file, trans_file, raw_todir, doc_todir, count=False):
    speaker_raws = {}
    speaker_trans = {}
    repeated_raws = 0
    repeated_trans = 0
    raws_new_files = set()
    with open(raws_file) as rf:
        num = 0
        for line in rf:
            line = line.strip()
            num += 1
            print num #, line
            (speaker, new_wav_file) = parse_raw_line(line)
            if not speaker:
                continue
            if speaker not in speaker_raws:
                speaker_raws[speaker] = []
                if not os.path.isdir(raw_todir + '/' + speaker):
                    os.mkdir(raw_todir + '/' + speaker)
            if speaker_raws[speaker].count(new_wav_file) != 0:
                repeated_raws += 1
                print "Repeated(discard reversed_time) raw file:", new_wav_file
                continue
            raws_new_files.add(new_wav_file)
            speaker_raws[speaker][new_wav_file] = gen_ffmpeg_command(line, new_wav_file, raw_todir + '/' + speaker)
    print "Discard reversed_time: %d repeated raws" % repeated_raws
    with open(trans_file) as tf:
        for line in tf:
            line = line.strip()
            (new_wav_file, transcription) = parse_trans_line(line)
            if not new_wav_file:
                continue
            if new_wav_file in speaker_trans:
                repeated_trans += 1
                # print "Repeated transcription:", line, "\n\t\t\t", new_wav_file, speaker_trans[new_wav_file]
                if speaker_trans[new_wav_file] != transcription:
                    print "WTFFF: reversed_time?: ", line
                    print "[%s] vs [%s]" % (speaker_trans[new_wav_file], transcription)
                    exit(-1)
                continue
            speaker_trans[new_wav_file] = transcription

    raw_line_num = sum([len(speaker_raws[speaker].keys()) for speaker in speaker_raws])
    print "Find %d[%d] raws(repeated %d), Transcription %d(repeated %d)" % (raw_line_num, len(raws_new_files), repeated_raws, len(speaker_trans), repeated_trans)
    no_trans_num = 0
    for nf in raws_new_files:
        if nf not in speaker_trans:
            no_trans_num += 1
    print "%d wav files have no transcription!!" % (no_trans_num)

    if not count:
        # write raw -> wav
        with open(doc_todir + "/ffmpeg.cmd", 'w') as f:
            for speaker in speaker_raws:
                for nf in speaker_raws[speaker]:
                    print >>f, speaker_raws[speaker][nf]
        # write transcriptions
        with open(doc_todir + "/transcriptions.all", 'w') as f:
            for speaker in speaker_trans:
                print >>f, speaker, speaker_trans[speaker]


if __name__ == "__main__":
    usage = '%prog [options] raw.find trans.txt wav_data_dir doc_dir '
    parser = OptionParser(usage)
    parser.add_option('--count', dest='count', default=False)
    (opt, argv) = parser.parse_args()

    if len(argv) != 4:
        print parser.print_help()
        exit(-1)
    run(argv[0], argv[1], argv[2], argv[3], count=(opt.count == 'True'))
