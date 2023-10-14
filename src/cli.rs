use clap::Parser;
use std::path::PathBuf;

/// The SILE typesetter reads an input file(s), by default in either SIL or XML format, and
/// processes them to generate an output file, by default in PDF format. The output will be written
/// to a file with the same name as the first input file with the extension changed to .pdf unless
/// the `--output` argument is used. Additional input or output formats can be handled by loading
/// a module with the `--use` argument to add support for them first.
#[derive(Parser, Debug)]
#[clap(author, name = "SILE", bin_name = "sile")]
pub struct Cli {
    /// Input document(s), by default in SIL or XML format.
    pub input: Option<Vec<PathBuf>>,

    /// Choose an alternative output backend.
    #[clap(short, long, value_name = "BACKEND")]
    pub backend: Option<String>,

    /// Override default document class.
    #[clap(short, long)]
    pub class: Option<String>,

    /// Show debug information for tagged aspects of SILE’s operation.
    #[clap(short, long, value_name = "DEBUGFLAG[,DEBUGFLAG]")]
    // TODO: switch to num_args(0..) to allow space separated inputs
    pub debug: Option<Vec<String>>,

    /// Evaluate Lua expression before processing input.
    #[clap(short, long, value_name = "EXRPESION")]
    pub evaluate: Option<Vec<String>>,

    /// Evaluate Lua expression after processing input.
    #[clap(short = 'E', long, value_name = "EXRPESION")]
    pub evaluate_after: Option<Vec<String>>,

    /// Choose an alternative font manager.
    #[clap(short, long, value_name = "FONTMANAGER")]
    pub fontmanager: Option<String>,

    /// Generate a list of dependencies in Makefile format.
    #[clap(short, long, value_name = "FILE")]
    pub makedeps: Option<PathBuf>,

    /// Explicitly set output file name.
    #[clap(short, long, value_name = "FILE")]
    pub output: Option<PathBuf>,

    /// Set document class options.
    #[clap(short = 'O', long)]
    pub option: Option<Vec<String>>,

    /// Include the contents of a SIL, XML, or other resource file before the input document content.
    ///
    /// The value should be a full filename with a path relative to PWD or an absolute path
    /// May be specified more than once.
    #[clap(short, long, value_name = "FILE")]
    pub preamble: Option<Vec<PathBuf>>,

    /// Include the contents of a SIL, XML, or other resource file after the input document content.
    ///
    /// The value should be a full filename with a path relative to PWD or an absolute path. May be
    /// specified more than once.
    #[clap(short = 'P', long, value_name = "FILE")]
    pub postamble: Option<Vec<PathBuf>>,

    /// Load and initialize a class, inputter, shaper, or other module before processing the main input.
    ///
    /// The value should be a loadable module name (with no extension, using `.` as a path separator) and will be loaded using SILE's module search path.
    /// Options may be passed to the module by enclosing `key=value` pairs in square brackets following the module name.
    /// This is particularly useful when the input document is not SIL or a natively recognized XML scheme
    /// and SILE needs to be taught new tricks before even trying to read the input file.
    /// If the module is a document class, it will replace `plain` as the default class for processing
    /// documents that do not specifically identify one to use.
    /// Because this executes before loading the document, it may even add an input parser or modify an existing one to support new file formats.
    /// Package modules will be added to the preamble to be loaded after the class is initialized.
    /// May be specified more than once.
    #[clap(
        short,
        long,
        value_name = "MODULE[[PARAMETER=VALUE[,PARAMETER=VALUE]]]"
    )]
    pub r#use: Option<Vec<String>>,

    /// Suppress warnings and informational messages during processing.
    #[clap(short, long)]
    pub quiet: bool,

    /// Display detailed location trace on errors and warnings.
    #[clap(short, long)]
    pub traceback: bool,

    /// version
    #[clap(short, long)]
}
