__author__ = 'feiteng'

import re

### 500001_94_ios.m4a_pb
def get_sid_spk_device(name):
    name = name.strip()
    if name.find('.') < 0:
        return None
    ###name.replace('.m4a_pb', '')
    name = name[:name.find('.')]
    name_parts = name.split('_')
    for i in range(0, len(name_parts)-1):
        if (name_parts[0].isdigit() == True) and (name_parts[1].isdigit() == True):
            break
        else:
            name_parts = name_parts[i+1:]
    assert len(name_parts) >= 3
    sid = name_parts[0]
    speaker = name_parts[1]
    device = name_parts[2]
    return (sid, speaker, device)

def get_key_value(line):
    line = line.strip()
    splits = line.split()
    key = splits[0]
    value = ' '.join(splits[1:])
    single_word = len(splits) == 2
    return (key.strip(), value.strip(), single_word)

def get_phone_map_dict(phone):
    lines = open(phone, 'r').readlines()
    phone_dict = dict()
    for line in lines:
        splits = line.strip().split()
        assert len(splits) == 2
        phone_dict[splits[1]] = splits[0]
    return phone_dict





