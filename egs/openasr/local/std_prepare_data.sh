#!/bin/bash

# Feiteng 
# 2014.12.23 2014.12.25 
# 2015.01.14 2015.10.23
# 2016.03.31
#
#
#
#
# Begin configuration
train=false
test=false
type=1

data=data
# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

if [ $# -ne 1 ]; then
 	echo "Argument should be the Corpus directory."
 	exit 1;
fi 

if [ $# != 1 ]; then
   echo "usage: local/std_prepare_data.sh <corpus-dir>"
   echo "e.g.:  local/std_prepare_data.sh /data/voxpop"
   echo "main options (for others, see top of script file)"
   echo "  --train                           # extract corpus/data/train"
   echo "  --test                            # extract corpus/data/test"
   exit 1;
fi

export LC_ALL=C

ROOTCORPUS=$1

# $0 ： 即命令本身，相当于C/C++中的argv[0]
# $1 ： 第一个参数.
# $#  参数的个数，不包括命令本身
# $@ ：参数本身的列表，也不包括命令本身
# $* ：和$@相同，但"$*" 和 "$@"(加引号)并不同，"$*"将所有的参数解释成一个字符串，而"$@"是一个参数数组。如下例所示
# -f file 检查file是否存在并是一个文件 -d 目录
# -x file 检查file是否存在并可执行
if $train && [ ! -d $ROOTCORPUS/data/train ]; then
	echo "Error: std_prepare_data.sh 语料库路径参数应该包含data/train目录."
	exit 1;
fi

if $test && [ ! -d $ROOTCORPUS/data/test ]; then
	echo "Error: std_prepare_data.sh 语料库路径参数应该包含data/test目录."
	exit 1;
fi

if $train || $test; then
	echo "##### $0 ..."
else
	echo "##### $0 Nothing TODO, EXIT."
	exit 0;
fi

if [ ! -f $ROOTCORPUS/doc/all_trans.txt ]; then
	echo "Error: std_prepare_data.sh 语料库路径参数应该包含$ROOTCORPUS/doc/all_trans.txt标注文件."
	exit 1;
fi

tmpdir=$data/local/tmp
mkdir -p $tmpdir

if $train;then
	echo "========================Train==========================="
	find $ROOTCORPUS/data/train -iname "*.wav" | sort > $tmpdir/train.flist
	dir=$data/train
	mkdir -p $dir ### 句子的标识ID为 ： data/train/speakerID/sentenceID -> speakerID_sentenceID_trn
	local/make_trans.py --type $type trn $tmpdir/train.flist $ROOTCORPUS/doc/all_trans.txt >(sort -k1 >$dir/text) \
		>(sort -k1 >$dir/wav.scp) $dir/utt2spk || exit 1;
    fi
	sleep 2
	utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt || exit 1;
fi

if $test;then
	echo "========================Test==========================="
	find $ROOTCORPUS/data/test -iname "*.wav" | sort > $tmpdir/test.flist
	dir=$data/test
	mkdir -p $dir

	local/make_trans.py --type $type tst $tmpdir/test.flist $ROOTCORPUS/doc/all_trans.txt >(sort -k1 >$dir/text) \
		>(sort -k1 >$dir/wav.scp) $dir/utt2spk || exit 1;
	utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt || exit 1;
fi

echo "##### $0 std_prepare_data.sh succeeded."

exit 0;

