# PowerUps

A command line tool to help me manage a large Xcode Instruments XML file. It's designed to process a bunch of includes and variables before running in Xcode and then remove the automatically generated code when the run has finished.

![Diagram of the powerups workflow](https://trycombine.com/images/timelane/powerups-workflow.png)

## Usage

This tool has a very specific use-case aimed at large XML files (like Xcode Instruments). I've written a blog post with more details here: https://trycombine.com/posts/xcode-powerups/

Generally, these are the steps to integrate with an Xcode Instruments project:

1. Add a Build/pre-action to run the powerups on your instruments file:

```
/path/to/powerups \
 $SOURCE_ROOT/Instrument/MyInstrument.instrpkg \
  --includesFolder \
 $SOURCE_ROOT/Instrument \
  --variables \
 $SOURCE_ROOT/Instrument/global-variables.json \
  --overwrite \
 > $SOURCE_ROOT/logs/powerups-log.txt
```

This pre-action will run the compiled `powerups` binary and feed it the `instrpkg` file and the given includes directory and global variables file. The output is saved to the given log text file.

2. Add a Run/post-action to clean up your `instrpkg` file so you can edit it manually if needed after running:

```
/path/to/powerups \
 $SOURCE_ROOT/Instrument/MyInstrument.instrpkg \
  --cleanup \
  --overwrite \
&& > $SOURCE_ROOT/logs/powerups-log.txt
```

That's it. When you run the instrument for testing, powerups will process the includes and variables, add the generated content in the package file, and finally when you close Instruments and stop running, it'll remove the generated content from your source file.

## Example

For a simple use case from the command line run the `run-demo.sh` script in the repo root folder.

## License

Copyright (c) Marin Todorov 2022 This code is provided under the MIT License.