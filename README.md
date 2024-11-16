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
  TMPDIR=<临时文件存放目录（默认值：/tmp）> \
  JOB_MAX=<最大进程数（最多5个，默认值：2）> \
  SHORT_EDGE=<压缩时的短边尺寸（默认值：2160）> \
  RESIZE_METHOD=<压缩方法（参考 ImageMagick 文档，默认值：resize）> \
  GRAY_SCALE=<识别灰阶图片时的分块边长（越小越精确，默认值：16）> \
  GRAY_THRESHOLD=<识别灰阶图片的阈值（越小越精确，默认值：0.16）> \
  GLOBAL_POSTFX=<全局后处理特效（即自定义 ImageMagick 指令，默认为空）> \
  GRAY_POSTFX=<灰阶后处理特效（同上，但此条只针对灰阶类色彩空间起效）> \
  ./myims <图片目录或zip>
```

轻度使用只需考虑更改 JOB_MAX 和 SHORT_EDGE。

当 GRAY_THRESHOLD 取值大于等于1时，将会把所有图片视为灰阶图片，这可能在某些场景下有用。

## 注意事项

请勿在相同 TMPDIR 配置下运行多个脚本，这可能导致文件丢失。

## 还未实现

- 支持 7z、rar 等压缩格式
- 根据内存自动管理进程数量
