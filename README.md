# MyIMS

基于 ImageMagick 实现的多进程图片压缩脚本。

## 基本依赖

- coreutils
- busybox awk / gawk
- imagemagick
- unzip
- zip

## 使用方法

```sh
./myims <图片目录或zip>
```

或者：
```sh
./myims <图片目录或zip1> <图片目录或zip2> <图片目录或zip3>
```

也可以：
```sh
./myims <<< "$(ls *.zip)"
```

## 修改参数

```sh
env \
  TMPDIR=<临时文件存放目录> \
  JOB_MAX=<最大进程数> \
  SHORT_EDGE=<压缩时的短边尺寸> \
  RESIZE_METHOD=<压缩方法> \
  GRAY_SCALE=<识别灰阶图片时的分块边长> \
  GRAY_THRESHOLD=<识别灰阶图片的阈值> \
  ./myims <图片目录或zip>
```

轻度使用只需考虑更改 JOB_MAX 和 SHORT_EDGE。

## 注意事项

请勿在相同 TMPDIR 配置下运行多个脚本，这可能导致文件丢失。

## 还未实现

- 支持 7z、rar 等压缩格式
- 根据内存自动管理进程数量
