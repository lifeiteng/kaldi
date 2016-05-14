#!/bin/bash
# Copyright 2012-2014  Johns Hopkins University (Author: Daniel Povey, Yenda Trmal)
# Apache 2.0

# begin configuration section.
cmd=run.pl
stage=0
decode_mbr=false
reverse=false
stats=true
beam=6
word_ins_penalty=0.0
min_lmwt=9
max_lmwt=20
iter=final
ground_truth='hyp' # ref 根据equal_pattern选择文本
ref_text=""

#end configuration section.

echo "$0 $@"  # Print the command line for logging
[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/score.sh [--cmd (run.pl|queue.pl...)] <data-dir> <lang-dir|graph-dir> <decode-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --stage (0|1|2)                 # start scoring script from part-way through."
  echo "    --decode_mbr (true/false)       # maximum bayes risk decoding (confusion network)."
  echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
  echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  echo "    --reverse (true/false)          # score with time reversed features "
  exit 1;
fi

data=$1
lang_or_graph=$2
dir=$3

symtab=$lang_or_graph/words.txt

for f in $symtab $dir/lat.1.gz $data/text; do
  [ ! -f $f ] && echo "score.sh: no such file $f" && exit 1;
done


ref_filtering_cmd="cat"
# [ -x local/wer_output_filter ] && ref_filtering_cmd="local/wer_output_filter"
[ -x local/wer_ref_filter ] && ref_filtering_cmd="local/wer_ref_filter"
hyp_filtering_cmd="cat"
# [ -x local/wer_output_filter ] && hyp_filtering_cmd="local/wer_output_filter"
[ -x local/wer_hyp_filter ] && hyp_filtering_cmd="local/wer_hyp_filter"


if $decode_mbr ; then
  echo "$0: scoring with MBR, word insertion penalty=$word_ins_penalty"
else
  echo "$0: scoring with word insertion penalty=$word_ins_penalty"
fi


mkdir -p $dir/scoring
if [ ! -z $ref_text ] && [ -f $ref_text ];then
  cat $ref_text | $ref_filtering_cmd > $dir/scoring/test_filt.txt || exit 1;
else
  cat $data/text | $ref_filtering_cmd > $dir/scoring/test_filt.txt || exit 1;
fi

if [ $stage -le 0 ]; then
  for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
    mkdir -p $dir/scoring/penalty_$wip/log
    if $decode_mbr ; then
      $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/penalty_$wip/log/best_path.LMWT.log \
        acwt=\`perl -e \"print 1.0/LMWT\"\`\; \
        lattice-scale --inv-acoustic-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
        lattice-add-penalty --word-ins-penalty=$wip ark:- ark:- \| \
        lattice-prune --beam=$beam ark:- ark:- \| \
        lattice-mbr-decode  --word-symbol-table=$symtab \
        ark:- ark,t:- \| \
        utils/int2sym.pl -f 2- $symtab '>' $dir/scoring/penalty_$wip/LMWT.txt.best || exit 1;
    else
      $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/penalty_$wip/log/best_path.LMWT.log \
        lattice-scale --inv-acoustic-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
        lattice-add-penalty --word-ins-penalty=$wip ark:- ark:- \| \
        lattice-best-path --word-symbol-table=$symtab ark:- ark,t:- \| \
        utils/int2sym.pl -f 2- $symtab '>' $dir/scoring/penalty_$wip/LMWT.txt.best || exit 1;
    fi
  done
fi

if [ $stage -le 1 ]; then
  for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
    for lmwt in `seq $min_lmwt $max_lmwt`; do
      cat $dir/scoring/penalty_$wip/$lmwt.txt.best | $hyp_filtering_cmd >$dir/scoring/penalty_$wip/$lmwt.txt.orig || exit 1;
      
      if $reverse; then # rarely-used option, ignore this.
        awk '{ printf("%s ",$1); for(i=NF; i>1; i--){ printf("%s ",$i); } printf("\n"); }' \
          <$dir/scoring/penalty_$wip/$lmwt.txt.orig >$dir/scoring/penalty_$wip/$lmwt.txt
      else
        mv $dir/scoring/penalty_$wip/$lmwt.txt.orig $dir/scoring/penalty_$wip/$lmwt.txt || exit 1;
      fi
    done

    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/penalty_$wip/log/score.LMWT.log \
      cat $dir/scoring/penalty_$wip/LMWT.txt \| \
      compute-wer --text --mode=present \
      ark:$dir/scoring/test_filt.txt  ark,p:- ">&" $dir/wer_LMWT_$wip || exit 1;
  done
fi


if [ $stage -le 2 ]; then

  for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
    for lmwt in $(seq $min_lmwt $max_lmwt); do
      # adding /dev/null to the command list below forces grep to output the filename
      grep WER $dir/wer_${lmwt}_${wip} /dev/null
    done
  done | utils/best_wer.sh  >& $dir/scoring/best_wer || exit 1

  best_wer_file=$(awk '{print $NF}' $dir/scoring/best_wer)
  best_wip=$(echo $best_wer_file | awk -F_ '{print $NF}')
  best_lmwt=$(echo $best_wer_file | awk -F_ '{N=NF-1; print $N}')

  if [ -z "$best_lmwt" ]; then
    echo "$0: we could not get the details of the best WER from the file $dir/wer_*.  Probably something went wrong."
    exit 1;
  fi

  if $stats; then
    mkdir -p $dir/scoring/wer_details
    echo $best_lmwt > $dir/scoring/wer_details/lmwt # record best language model weight
    echo $best_wip > $dir/scoring/wer_details/wip # record best word insertion penalty

    $cmd $dir/scoring/log/stats1.log \
      cat $dir/scoring/penalty_$best_wip/$best_lmwt.txt \| \
      align-text --special-symbol="'***'" ark:$dir/scoring/test_filt.txt ark:- ark,t:- \|  \
      utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" \| tee $dir/scoring/wer_details/per_utt \|\
       utils/scoring/wer_per_spk_details.pl $data/utt2spk \> $dir/scoring/wer_details/per_spk || exit 1;

    $cmd $dir/scoring/log/stats2.log \
      cat $dir/scoring/wer_details/per_utt \| \
      utils/scoring/wer_ops_details.pl --special-symbol "'***'" \| \
      sort -b -i -k 1,1 -k 4,4rn -k 2,2 -k 3,3 \> $dir/scoring/wer_details/ops || exit 1;

    (
      # local/wer_ops_details.py $dir/scoring/wer_details/per_utt \
      #   $dir/scoring/wer_details/per_utt.ana || exit 1;
      export LC_ALL=C
      cat $dir/scoring/penalty_$best_wip/$best_lmwt.txt | \
            align-text --special-symbol="***" ark:$dir/scoring/test_filt.txt ark:- ark,t:$dir/scoring/wer_details/per_utt.all 2>/dev/null
      awk '{printf $1" ref "; for(i=2;i<NF;i+=3) printf $i" "; print "";}' $dir/scoring/wer_details/per_utt.all \
        >$dir/scoring/wer_details/per_utt.ref.t || exit 1;
      awk '{printf $1" hyp "; for(i=3;i<=NF;i+=3) printf $i" "; print "";}' $dir/scoring/wer_details/per_utt.all \
        >$dir/scoring/wer_details/per_utt.hyp.t || exit 1;
      awk 'FNR==NR{C[$1]=$0;} FNR<NR{if ($1 in C) {print C[$1]; print $0;}}' $dir/scoring/wer_details/per_utt.ref.t \
        $dir/scoring/wer_details/per_utt.hyp.t >$dir/scoring/wer_details/per_utt.ref_hyp.t || exit 1;

      # wc -l $dir/scoring/wer_details/per_utt.ref_hyp.t

      local/wer/wer_ops_details.py --ground-truth $ground_truth --equal-pattern local/wer/equal_pattern.txt $dir/scoring/wer_details/per_utt.ref_hyp.t \
        $dir/scoring/wer_details/per_utt.ana $dir/scoring/wer_details/per_utt.ref_hyp || exit 1;

      cat $dir/scoring/wer_details/per_utt.ref_hyp | \
        awk '{if($2 == "ref") {$2=""; print $0;}}' | sort >$dir/scoring/wer_details/correct_ref.txt || exit 1;
      cat $dir/scoring/wer_details/per_utt.ref_hyp | \
        awk '{if($2 == "hyp") {$2=""; print $0;}}' | sort >$dir/scoring/wer_details/correct_hyp.txt || exit 1;

      compute-wer --text --mode=present ark:$dir/scoring/wer_details/correct_ref.txt \
        ark,p:$dir/scoring/wer_details/correct_hyp.txt >$dir/wer_correct  2>/dev/null|| exit 1;

      cat $dir/scoring/wer_details/per_utt | grep "0 0 0" | awk '{print $1;}' | sort | uniq > $dir/scoring/wer_details/tmp.allright
      awk 'FNR==NR{C[$1]=1;} FNR<NR{if(!($1 in C)) { if($2 != "op") print $0;}}' $dir/scoring/wer_details/tmp.allright \
        $dir/scoring/wer_details/per_utt | grep -v "#csid" | sort -V >$dir/scoring/wer_details/per_utt.clean

      echo "----------------------------------"
      echo "Before correct WER"
      cat $dir/wer_${best_lmwt}_${best_wip}
      echo "After correct WER"
      cat $dir/wer_correct
      echo "----------------------------------"
      rm -f $dir/scoring/wer_details/*.t
      rm -f $dir/scoring/wer_details/per_utt.all
      rm -f $dir/scoring/wer_details/tmp.allright
    )

    $cmd $dir/scoring/log/wer_bootci.log \
      compute-wer-bootci \
        ark:$dir/scoring/test_filt.txt ark:$dir/scoring/penalty_$best_wip/$best_lmwt.txt \
        '>' $dir/scoring/wer_details/wer_bootci || exit 1;

  fi
fi

# If we got here, the scoring was successful.
# As a  small aid to prevent confusion, we remove all wer_{?,??} files;
# these originate from the previous version of the scoring files
rm $dir/wer_{?,??} 2>/dev/null

exit 0;
