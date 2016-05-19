#!/usr/bin/python
# -*- encoding: utf-8 -*-
__author__ = 'Feiteng'
import sys
import os
import re
import logging
from collections import defaultdict

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
handler.setLevel(logging.INFO)
formatter = logging.Formatter(
    '%(asctime)s [%(filename)s:%(lineno)s - %(funcName)s - %(levelname)s ] %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.info('Parse Component')


class TransitionModel:
    def __init__(self):
        self.lines = []

    def Read(self, fp=file):
        line = fp.readline()
        assert line.find('<TransitionModel>') >= 0
        self.lines.append(line)
        while True:
            line = fp.readline()
            if line.find('</TransitionModel>') >= 0:
                self.lines.append(line)
                break
            self.lines.append(line)
        logger.info('DONE.')

    def Write(self, f=file):
        for l in self.lines:
            print >> f, l,
        logger.info('DONE.')


class Component(object):
    def __init__(self):
        pass

    def Read(self, fp):
        pass

    def Write(self, f):
        pass

    def Name(self):
        return self.input


class Vector:
    def __init__(self):
        self.values = []

    def Read(self, fp):
        line = fp.readline()
        start_idx = line.find('[')
        end_idx = line.find(']')
        assert start_idx >= 0
        assert end_idx > start_idx
        self.values = [float(v) for v in line[start_idx + 1:end_idx].split()]

    def Write(self, f):
        print >> f, '[ %s ]' % (' '.join([str(v) for v in self.values]))

    def Dim(self):
        return len(self.values)

    def RemoveValues(self, idxs):
        keep = []
        for i in range(0, self.Dim()):
            if i not in idxs:
                keep.append(self.values[i])


class Matrix:
    def __init__(self):
        self.rows = []

    def Read(self, fp):
        while True:
            line = fp.readline()
            if line.find('[') >= 0:
                line = line[line.find('[') + 1:]

            if line.strip().endswith(']'):
                splits = line.strip().replace(']', '').split()
                self.rows.append([float(v) for v in splits])
                break
            else:
                splits = line.strip().split()
                self.rows.append([float(v) for v in splits])
        # check health
        assert len(self.rows) >= 1
        num_cols = len(self.rows[0])
        for i in range(1, len(self.rows)):
            assert num_cols == len(self.rows[i])

    def Write(self, f):
        num_rows = len(self.rows)
        print >> f, '['
        for i in range(0, num_rows):
            if i == num_rows - 1:
                print >> f, ' '.join([str(v) for v in self.rows[i]]), ']'
            else:
                print >> f, ' '.join([str(v) for v in self.rows[i]])

    def NumRows(self):
        return len(self.rows)

    def NumCols(self):
        return len(self.rows[0])

    def Value(self, r, c):
        return self.rows[r][c]

    def RemoveRows(self, rows):
        pass

    def RemoveCols(self, cols):
        pass


class FixedAffineComponent(Component):
    def __init__(self):
        self.info = ''
        self.LinearParams = Matrix()
        self.BiasParams = Vector()
        self.end_info = ''

    def Read(self, fp):
        line = fp.readline().strip()
        assert line.startswith('<ComponentName>')
        assert line.endswith('[')
        assert line.find('<LinearParams>') > 0
        self.info = line[:line.find('[') - 1]
        self.LinearParams.Read(fp)
        self.BiasParams.Read(fp)
        self.end_info = fp.readline()

    def Write(self, f):
        print >> f, self.info,
        self.LinearParams.Write(f)
        print >> f, '<BiasParams>',
        self.BiasParams.Write(f)
        print >> f, self.end_info,


class NaturalGradientAffineComponent(FixedAffineComponent):
    def __init__(self):
        super(NaturalGradientAffineComponent, self).__init__()

    def Read(self, fp):
        super(NaturalGradientAffineComponent, self).Read(fp)

    def Write(self, f):
        super(NaturalGradientAffineComponent, self).Write(f)


class RectifiedLinearComponent(Component):
    def __init__(self):
        self.name = ''
        self.Dim = -1
        self.ValueAvg = Vector()
        self.DerivAvg = Vector()
        self.end_info = ''

    def Read(self, fp):
        # <ComponentName> Tdnn_0_relu <RectifiedLinearComponent> <Dim> 800 <ValueAvg>  [
        position = fp.tell()
        line = fp.readline()
        m = re.match(
            '^<ComponentName> (.+) <RectifiedLinearComponent> <Dim> (\d+) <ValueAvg>\s+\[',
            line)
        assert m
        self.name = m.group(1)
        self.Dim = int(m.group(2))
        fp.seek(position, 0)
        self.ValueAvg.Read(fp)
        self.DerivAvg.Read(fp)
        # <Count> 1.105693e+09 </RectifiedLinearComponent>
        self.end_info = fp.readline()

    def Prune(self):
        pass

    def Write(self, f):
        print >> f, '<ComponentName> {0} <RectifiedLinearComponent> <Dim> {1} <ValueAvg> '.format(
            self.name, self.Dim),
        self.ValueAvg.Write(f)
        print >> f, '<DerivAvg>',
        self.DerivAvg.Write(f)
        print >> f, self.end_info,


class NormalizeComponent(Component):
    def __init__(self):
        self.name = ''
        self.InputDim = -1
        self.end_info = ''

    def Read(self, fp):
        # <ComponentName> Tdnn_0_renorm <NormalizeComponent> <InputDim> 800 <TargetRms> 1 <AddLogStddev> F </NormalizeComponent>
        line = fp.readline()
        m = re.match(
            '<ComponentName> (.+) <NormalizeComponent> <InputDim> (\d+) (.+)',
            line)
        self.name = m.group(1)
        self.InputDim = int(m.group(2))
        self.end_info = m.group(3)

    def Prune(self):
        # 修改InputDim
        pass

    def Write(self, f):
        print >> f, "<ComponentName> {0} <NormalizeComponent> <InputDim> {1} {2}".format(
            self.name, self.InputDim, self.end_info)


class FixedScaleComponent(Component):
    def __init__(self):
        self.lines = []

    def Read(self, fp):
        # <ComponentName> Final-fixed-scale <FixedScaleComponent> <Scales> [
        self.lines.append(fp.readline())
        # </FixedScaleComponent>
        line = fp.readline()
        assert line.strip().endswith('</FixedScaleComponent>')
        self.lines.append(line)

    def Write(self, f):
        for l in self.lines:
            print >> f, l,


class LogSoftmaxComponent(Component):
    def __init__(self):
        self.lines = []

    def Read(self, fp):
        # <ComponentName> Final_log_softmax <LogSoftmaxComponent> <Dim> 4982 <ValueAvg>  [ ]
        # <DerivAvg>  [ ]
        # <Count> 0 </LogSoftmaxComponent>
        self.lines.append(fp.readline())
        self.lines.append(fp.readline())
        line = fp.readline()
        assert line.strip().endswith('</LogSoftmaxComponent>')
        self.lines.append(line)

    def Write(self, f):
        for l in self.lines:
            print >> f, l,


def NewComponent(type):
    if type == 'FixedAffineComponent':
        return FixedAffineComponent()
    elif type == 'NaturalGradientAffineComponent':
        return NaturalGradientAffineComponent()
    elif type == 'RectifiedLinearComponent':
        return RectifiedLinearComponent()
    elif type == 'LogSoftmaxComponent':
        return LogSoftmaxComponent()
    elif type == 'FixedScaleComponent':
        return FixedScaleComponent()
    elif type == 'NormalizeComponent':
        return NormalizeComponent()
    else:
        logger.error('Not known Component type!')


class AmNnetSimple:
    def __init__(self):
        self.transition_model = TransitionModel()
        self.nodes = defaultdict(lambda : {'index':-1, 'component_name': '', 'component': Component(), 'input':''})
        self.nodes_lines = []
        self.num_components_line = ''
        self.end_line = ''

        self.index2nodes = dict()

    def Read(self, fp):
        self.transition_model.Read(fp)
        line = fp.readline()
        assert line.find('<Nnet3>') >= 0
        while True:
            position = fp.tell()
            line = fp.readline()
            if line.find('</Nnet3>') >= 0:
                self.end_line = line
                break
            elif line.find('-node name') >= 0:
                m = re.match('.*node name=(.+)\s.*', line)
                assert m is not None
                if line.find('input-node') >= 0 or line.find(
                        'output-node') >= 0:
                    self.nodes[m.group(1)] = {'index': len(self.nodes_lines),
                                              'component_name': m.group(1),
                                              'component': Component(),
                                              'input': ''}
                    assert not self.index2nodes.has_key(len(self.nodes_lines))
                    self.index2nodes[len(self.nodes_lines)] = m.group(1)
                else:
                    m = re.match(
                        '.*component-node name=(.+) component=(.+) input=(.+)$',
                        line)
                    assert m is not None
                    self.nodes[m.group(1)] = {'index': len(self.nodes_lines),
                                              'component_name': m.group(2),
                                              'component': Component(),
                                              'input': m.group(3)}
                    assert not self.index2nodes.has_key(len(self.nodes_lines))
                    self.index2nodes[len(self.nodes_lines)] = m.group(1)
                self.nodes_lines.append(line)

            elif line.find('<NumComponents>') >= 0:
                self.num_components_line = line
            elif not line.strip():
                pass
            else:
                logger.info('Start Parse Components...')
                # print "LINE:", line
                m = re.match('.*<ComponentName> (\S+) <(\S+)>\s.+', line)
                assert m
                # name = self.nodes[m.group(1)]['component'].Name()
                logger.info("Name:" + m.group(1))
                # print "Nodes:", self.nodes.keys()
                assert self.nodes.has_key(m.group(1))
                self.nodes[m.group(1)]['component'] = NewComponent(m.group(2))

                fp.seek(position, 0)
                self.nodes[m.group(1)]['component'].Read(fp)

                # exit(-1)

        logger.info('DONE.')

    def Prune(self):
        # step1 TODO io_norm
        pass

        # step2 Prune

    def Write(self, f):
        self.transition_model.Write(f)
        print >> f, '<Nnet3> '
        for node_line in self.nodes_lines:
            print >> f, node_line,
        print >> f, '\n', self.num_components_line,
        # TODO write Componments
        for idx in self.index2nodes:
            node = self.index2nodes[idx]
            self.nodes[node]['component'].Write(f)

        print >> f, self.end_line
