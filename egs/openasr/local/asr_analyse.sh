
LMWT=9
suffix="wer"
symtab=exp/backup/tri3/graph_tg/words.txt
data=data_all_fbank/native
dir=exp/nnet3/lstm_bidirectional_ld0_layers3_lr0.0003_rpd128_mpc2.0/decode_native
compare_ref_tra=""

. ./path.sh
. ./utils/parse_options.sh
set -e

mkdir -p asr/analyse

# cat $dir/scoring/$LMWT.tra | utils/int2sym.pl -f 2- $symtab | sed 's:\<UNK\>::g' | sort >asr/analyse/tmp.txt
# 	awk 'FNR=NR{W[$1]=$2;} FNR<NR{k=$1; $1=""; print Z[k], $0;}' $data/wav.scp

# exit 1

cat $dir/scoring/$LMWT.tra | utils/int2sym.pl -f 2- $symtab | sed 's:\<UNK\>::g' | sort | \
	awk 'FNR==NR{W[$1]=$2;} FNR<NR{k=$1; $1=""; print W[k], $0;}' $data/wav.scp - | \
	rev | cut -d"/" -f1 | rev >asr/analyse/$suffix.tra

ref=asr/analyse/text
if [ ! -z $compare_ref_tra ]; then 
	cat $compare_ref_tra | utils/int2sym.pl -f 2- $symtab >asr/analyse/text || exit 1;
else
	cp $data/text asr/analyse/text || exit 1;
fi

cat $dir/scoring/$LMWT.tra | utils/int2sym.pl -f 2- $symtab | \
	align-text --special-symbol='***' ark:$ref ark:- ark,t:- | \
	utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" | \
	awk 'FNR==NR{W[$1]=$2;} FNR<NR{k=$1; $1=""; print W[k], $0;}' $data/wav.scp - | \
	rev | cut -d"/" -f 1 | rev >asr/analyse/$suffix.per_utt.t

grep "0 0 0" asr/analyse/$suffix.per_utt.t | awk '{print $1;}' | grep -v -f - asr/analyse/$suffix.per_utt.t >asr/analyse/$suffix.per_utt
rm -f asr/analyse/$suffix.per_utt.t

# cat $dir/scoring/$LMWT.tra | utils/int2sym.pl -f 2- $symtab | sed 's:\<UNK\>::g' | compute-wer --text --mode=present \
#      ark:data_adaplr/test/text ark,p:-

# cat $dir/scoring/$LMWT.tra | utils/int2sym.pl -f 2- $symtab | sed 's:\<UNK\>::g' | compute-wer --text --mode=present \
#      ark:$dir/scoring/test_filt.txt ark,p:-
exit 0;
