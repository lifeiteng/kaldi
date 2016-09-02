#!/usr/bin/env python

# Copyright 2016 Vijayaditya Peddinti
# Apache 2.0

from __future__ import print_function
import argparse
import sys
import os
import subprocess
import errno
import copy
import shutil
import warnings
# import random
import numpy.random as random

# random.seed(0)


def CheckFiles(input_data_dir, check_duration=False):
    check_files = ['spk2utt', 'text', 'utt2spk', 'wav.scp']
    if check_duration:
        check_files.append('utt2dur')
    for file_name in check_files:
        file_name = '{0}/{1}'.format(input_data_dir, file_name)
        if not os.path.exists(file_name):
            raise Exception("There is no such file {0}".format(file_name))


def GetArgs():
    # we add compulsary arguments as named arguments for readability
    parser = argparse.ArgumentParser(
        description="""
    Add noise to wave file.""",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument(
        "--noise", type=str, required=True, help="Noise type to be added.")
    parser.add_argument(
        "--random-seed", type=int, required=False, help="random seed.")
    parser.add_argument(
        "--snr-db", type=float, required=True, help="Target snr db.")
    parser.add_argument("--noise-data-dir", type=str, required=True)
    parser.add_argument("--input-data-dir", type=str, required=True)
    parser.add_argument("--output-data-dir", type=str, required=True)

    print(' '.join(sys.argv))
    args = parser.parse_args()
    if args.random_seed is not None:
        print("Random Seed: %d" % (args.random_seed))
        random.seed(args.random_seed)

    return args


def RunKaldiCommand(command, wait=True):
    """ Runs commands frequently seen in Kaldi scripts. These are usually a
        sequence of commands connected by pipes, so we use shell=True """
    p = subprocess.Popen(
        command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    if wait:
        [stdout, stderr] = p.communicate()
        if p.returncode is not 0:
            raise Exception(
                "There was an error while running the command {0}\n".format(
                    command) + "-" * 10 + "\n" + stderr)
        return stdout, stderr
    else:
        return p


def MakeDir(dir):
    try:
        os.mkdir(dir)
    except OSError as exc:
        if exc.errno != errno.EEXIST:
            raise exc
        raise Exception("Directory {0} already exists".format(dir))
        pass


def ParseFileToDict(file, assert2fields=False, value_processor=None):
    if value_processor is None:
        value_processor = lambda x: x[0]

    dict = {}
    for line in open(file, 'r'):
        parts = line.split()
        if assert2fields:
            assert (len(parts) == 2)

        dict[parts[0]] = value_processor(parts[1:])
    return dict


def WriteDictToFile(dict, file_name):
    file = open(file_name, 'w')
    keys = dict.keys()
    keys.sort()
    for key in keys:
        value = dict[key]
        if type(value) in [list, tuple]:
            if type(value) is tuple:
                value = list(value)
            value.sort()
            value = ' '.join(value)
        file.write('{0}\t{1}\n'.format(key, value))
    file.close()


def ParseDataDirInfo(data_dir):
    data_dir_file = lambda file_name: '{0}/{1}'.format(data_dir, file_name)

    utt2spk = ParseFileToDict(data_dir_file('utt2spk'))
    spk2utt = ParseFileToDict(
        data_dir_file('spk2utt'), value_processor=lambda x: x)
    text = ParseFileToDict(
        data_dir_file('text'), value_processor=lambda x: " ".join(x))
    wavscp = ParseFileToDict(data_dir_file('wav.scp'), assert2fields=False)
    utt2dur = ParseFileToDict(
        data_dir_file('utt2dur'), value_processor=lambda x: float(x[0]))
    utt2uniq = None
    if os.path.exists(data_dir_file('utt2uniq')):
        utt2uniq = ParseFileToDict(data_dir_file('utt2uniq'))
    return wavscp, utt2spk, spk2utt, text, utt2dur, utt2uniq


def WriteCombinedDirFiles(output_dir, wavscp, utt2spk, spk2utt, text, utt2dur,
                          utt2uniq):
    out_dir_file = lambda file_name: '{0}/{1}'.format(output_dir, file_name)
    WriteDictToFile(wavscp, out_dir_file('wav.scp'))
    WriteDictToFile(utt2spk, out_dir_file('utt2spk'))
    WriteDictToFile(spk2utt, out_dir_file('spk2utt'))
    WriteDictToFile(text, out_dir_file('text'))
    if utt2uniq is not None:
        WriteDictToFile(utt2uniq, out_dir_file('utt2uniq'))
    if utt2dur is not None:
        WriteDictToFile(utt2dur, out_dir_file('utt2dur'))


def SelectNoiseWave(wavscp,
                    spk2utt,
                    utt2dur,
                    noise_type,
                    mixed_weights,
                    weight_rand=False):
    if noise_type != 'mixed':
        assert noise_type in spk2utt
        if weight_rand:
            weights = [utt2dur[ut] for ut in spk2utt[noise_type]]
            sum_weights = sum(weights)
            weights = [v / sum_weights for v in weights]
            utt = random.choice(spk2utt[noise_type], p=weights)
        else:
            utt = random.choice(spk2utt[noise_type])
    else:
        if weight_rand:
            utt = random.choice(wavscp.keys(), p=mixed_weights)
        else:
            utt = random.choice(wavscp.keys())
    return wavscp[utt], random.random() * float(utt2dur[utt])


def CorruptNoise(input_dir, noise_dir, output_dir, noise_type, snr_db):
    wav_addnoise = lambda input, noise, snr, shfit: 'wav-addnoise --snr-db={snr} --shift={shift} "{input}" "{noise}" - |'.format(input=input,
        noise=noise, snr=snr, shift=shift)

    noisewavscp, utt2spk, noisespk2utt, text, noiseutt2dur, utt2uniq = ParseDataDirInfo(
        noise_dir)

    wavscp, utt2spk, spk2utt, text, utt2dur, utt2uniq = ParseDataDirInfo(
        input_dir)
    shfit = 0
    speakers = spk2utt.keys()
    speakers.sort()

    weights = [noiseutt2dur[ut] for ut in noisewavscp.keys()]
    sum_weights = sum(weights)
    weights = [v / sum_weights for v in weights]

    for speaker in speakers:
        utts = spk2utt[speaker]  # this is an assignment of the reference
        utts.sort()
        for ut in utts:
            wave_file = wavscp[ut]
            corrupt_noise_wav = None
            snr_db_random = random.uniform(snr_db - 2.5, snr_db + 2.5)
            noise_file, shift = SelectNoiseWave(
                noisewavscp, noisespk2utt, noiseutt2dur, noise_type, weights)
            corrupt_noise_wav = wav_addnoise(wave_file, noise_file,
                                             snr_db_random, shift)
            assert corrupt_noise_wav
            wavscp[ut] = corrupt_noise_wav

    WriteCombinedDirFiles(output_dir, wavscp, utt2spk, spk2utt, text, utt2dur,
                          utt2uniq)


def Main():

    args = GetArgs()

    CheckFiles(args.input_data_dir)
    MakeDir(args.output_data_dir)
    feat_lengths = {}
    segments_file = '{0}/segments'.format(args.input_data_dir)
    if args.noise_data_dir:
        RunKaldiCommand("utils/data/get_utt2dur.sh {0}".format(
            args.noise_data_dir))
    if args.noise not in ['white', 'pink']:
        CheckFiles(args.noise_data_dir, check_duration=True)

    CorruptNoise(args.input_data_dir, args.noise_data_dir,
                 args.output_data_dir, args.noise, args.snr_db)

    RunKaldiCommand("utils/fix_data_dir.sh {0}".format(args.output_data_dir))


if __name__ == "__main__":
    Main()
