

nnet_dir=exp/tri3_ali_fbank40_h5t2048_ReLU_NP_SVD256_DCT_smbr_0.00000001

# echo "496666" | sudo -S nvidia-smi -c 0
# echo "496666" | sudo -S pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY nvidia-smi -c 0

# rm -rf data/local/dict/
# mkdir -p data/local/dict
# cat /data/dictionary/{TEDLIUM.150K.dic,9001.dict} >data/local/dict/lexicon_9001_ted.txt
# local/std_prepare_dict.sh --data data --phoneset 9001 --noise false data/local/dict/lexicon_9001_ted.txt || exit 1;
# utils/prepare_lang.sh --share-silence-phones true --num-sil-states 3 --position-dependent-phones false \
#     data/local/dict '!SIL' data/local/lang_tmp data/lang_9001_sil || exit 1;

local/cleanup/cleanup_nnet2.sh --nj 6 data_fbank/openasr-01/train data/lang_9001_sil \
	$nnet_dir data_fbank/openasr-01/train_cleanup

