from __future__ import print_function

import argparse
import collections
import datetime
import glob
import json
import multiprocessing
import os
import sys

import chainer
import chainer.cuda
import chainermn
import dataset
from chainer import training
from chainer.training import extensions

os.environ["CHAINER_TYPE_CHECK"] = "0"


if chainer.__version__.startswith('1.'):
    import models_v1.alex as alex
    import models_v1.googlenet as googlenet
    import models_v1.googlenetbn as googlenetbn
    import models_v1.nin as nin
    import models_v1.resnet50 as resnet50
else:
    import models_v2.alex as alex
    import models_v2.googlenet as googlenet
    import models_v2.googlenetbn as googlenetbn
    import models_v2.nin as nin
    import models_v2.resnet50 as resnet50
    import models_v2.resnet50_akiba as resnet50_akiba
    import models_v2.dilated_vgg as dilated_vgg

archs = {
    'alex': alex.Alex,
    'googlenet': googlenet.GoogLeNet,
    'googlenetbn': googlenetbn.GoogLeNetBN,
    'nin': nin.NIN,
    'resnet50': resnet50.ResNet50,
    'resnet50_akiba': resnet50_akiba.ResNet50,
}


def main():
    info = collections.OrderedDict()

    parser = argparse.ArgumentParser(
        description='Learning convnet from ILSVRC2012 dataset')
    parser.add_argument('train', help='Path to training image-label list file')
    parser.add_argument('val', help='Path to validation image-label list file')
    parser.add_argument('--root_train', default='.',
                        help='Root directory path of training image files')
    parser.add_argument('--root_val', default='.',
                        help='Root directory path of validation image files')
    parser.add_argument('--arch', '-a', choices=archs.keys(),
                        default='resnet50_akiba', help='Convnet architecture')
    parser.add_argument('--batchsize', '-B', type=int, default=32,
                        help='Learning minibatch size')
    parser.add_argument('--loaderjob', '-j', type=int,
                        help='Number of parallel data loading processes')
    parser.add_argument('--out', '-o', default='result',
                        help='Output directory')
    parser.add_argument('--communicator', default='hierarchical')
    parser.set_defaults(test=False)
    args = parser.parse_args()

    #
    # ChainerMN initialization
    #
    comm = chainermn.create_communicator(args.communicator)
    device = comm.intra_rank
    chainer.cuda.get_device(device).use()
    chainer.cuda.set_max_workspace_size(1 * 1024 * 1024 * 1024)

    #
    # Logging
    #
    if comm.rank == 0:
        result_directory = args.out
    else:
        import tempfile
        result_directory = tempfile.mkdtemp(dir='/tmp/')

    #
    # Model
    #
    model = archs[args.arch]()
    model.to_gpu()

    #
    # Dataset
    #
    if comm.rank == 0:
        train = dataset.PreprocessedDataset(
            args.train, args.root_train, model.insize)
    else:
        train = None
    train = chainermn.scatter_dataset(train, comm)

    multiprocessing.set_start_method('forkserver')
    train_iter = chainer.iterators.MultiprocessIterator(
        train, args.batchsize, n_processes=args.loaderjob)

    #
    # Optimizer
    #
    global_batchsize = comm.size * args.batchsize
    lr = 0.1 * global_batchsize / 256
    if comm.rank == 0:
        print('global_batchsize:', global_batchsize)
        print('Num of GPUs:', comm.size)

    weight_decay = 0.0001
    optimizer = chainer.optimizers.MomentumSGD(lr=lr, momentum=0.9)
    optimizer = chainermn.create_multi_node_optimizer(optimizer, comm)
    optimizer.setup(model)
    optimizer.add_hook(chainer.optimizer.WeightDecay(weight_decay))
    info['training'] = {
        'local_batchsize': args.batchsize,
        'global_batchsize': global_batchsize,
        'lr': lr
    }

    #
    # Trainer
    #
    log_interval = (10, 'iteration')
    stop_trigger = (200, 'iteration')

    updater = training.StandardUpdater(train_iter, optimizer, device=device)
    trainer = training.Trainer(updater, stop_trigger, result_directory)

    log_report_ext = extensions.LogReport(trigger=log_interval)
    trainer.extend(log_report_ext)

    if comm.rank == 0:
        trainer.extend(extensions.ProgressBar(update_interval=10))

    trainer.run()


if __name__ == '__main__':
    main()
