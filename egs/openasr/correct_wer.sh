

# grep "\sref " per_utt | awk '{$2=""; $1=""; print $0;}' | sed 's/\*\*\*//g' >tmp/ref
# grep "\shyp " per_utt | awk '{$2=""; $1=""; print $0;}' | sed 's/\*\*\*//g' >tmp/hyp

# dict=/Users/feiteng/GIT/water-house/openasr/asr-dicts/lexicon.txt

# python local/werpp.py tmp/ref tmp/hyp

# grep "\sref " per_utt | awk '{$2=""; print $0;}' | sed 's/\*\*\*//g' >tmp/ref_kv
# grep "\shyp " per_utt | awk '{$2=""; print $0;}' | sed 's/\*\*\*//g' >tmp/hyp_kv

# python local/corrected_wer.py tmp/ref_kv tmp/hyp_kv


# cat tmp/test_filt.txt | awk '{$1=""; print $0;}' >tmp/ref
# cat tmp/18.txt | awk '{$1=""; print $0;}' >tmp/hyp

# dict=/Users/feiteng/GIT/water-house/openasr/asr-dicts/lexicon.txt

# python local/werpp.py tmp/ref tmp/hyp

cat tmp/test_filt.txt | awk '{print $0;}' >tmp/ref_kv
cat tmp/18.txt | awk '{print $0;}' >tmp/hyp_kv

python local/corrected_wer.py tmp/ref_kv tmp/hyp_kv