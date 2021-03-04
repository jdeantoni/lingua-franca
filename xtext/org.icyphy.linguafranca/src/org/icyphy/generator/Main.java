/**
 * Stand-alone version of the Lingua Franca compiler (lfc).
 */
package org.icyphy.generator;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.FileTime;
import java.util.Arrays;
import java.util.LinkedList;
import java.util.List;
import java.util.Properties;
import java.util.stream.Collectors;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.Option;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.eclipse.emf.common.util.URI;
import org.eclipse.emf.ecore.resource.Resource;
import org.eclipse.emf.ecore.resource.ResourceSet;
import org.eclipse.xtext.generator.GeneratorDelegate;
import org.eclipse.xtext.generator.JavaIoFileSystemAccess;
import org.eclipse.xtext.util.CancelIndicator;
import org.eclipse.xtext.validation.CheckMode;
import org.eclipse.xtext.validation.IResourceValidator;
import org.eclipse.xtext.validation.Issue;
import org.eclipse.xtext.xbase.lib.ObjectExtensions;
import org.eclipse.xtext.xbase.lib.Procedures.Procedure1;
import org.icyphy.ASTUtils;
import org.icyphy.LinguaFrancaStandaloneSetup;

import com.google.inject.Inject;
import com.google.inject.Injector;
import com.google.inject.Provider;

/**
 * Standalone version of the Lingua Franca compiler (lfc).
 * 
 * @author{Marten Lohstroh <marten@berkeley.edu>}
 */
public class Main {
    
    /**
     * The location of the class file of this class inside of the jar.
     */
    private static String MAIN_PATH_IN_JAR = String.join(File.separator,
            new String[] { "!", "org", "icyphy", "generator", "Main.class" });
    
    /**
     * The location of the the jar relative to the root of the source tree.
     */
    private static String JAR_PATH_IN_SRC_TREE = String.join(File.separator,
            new String[] { "org.icyphy.linguafranca", "build", "libs",
                    "org.icyphy.linguafranca-1.0.0-SNAPSHOT-all.jar" });
    /**
     * The location of the jar relative to the root of the file system. 
     */
    private static String JAR_PATH = Main.class.getResource("Main.class")
            .toString().replace("jar:file:", "").replace(MAIN_PATH_IN_JAR, "");
    
    /**
     * The root of the source tree relative to the root of the file system.
     */
    private static String SRC_PATH = JAR_PATH.replace(
            "build/libs/org.icyphy.linguafranca-1.0.0-SNAPSHOT-all.jar", "")
            + "src/org";
    
    /**
     * ANSI sequence color escape sequence for red bold font.
     */
    private final static String RED_BOLD = "\033[1;31m";

    /**
     * ANSI sequence color escape sequence for ending red bold font.
     */
    private final static String END_RED_BOLD = "\033[0m";
    
    /**
     * ANSI sequence color escape sequence for bold font.
     */
    private final static String BOLD = "\u001b[1m";
    
    /**
     * ANSI sequence color escape sequence for ending bold font.
     */
    private final static String END_BOLD = "\u001b[0m";
    
    /**
     * Header used when printing messages.
     */
    private final static String HEADER = bold("lfc: ");
    
    /**
     * Object for interpreting command line arguments.
     */
    protected CommandLine cmd;
    
    /**
     * Injected resource provider. 
     */
    @Inject
    private Provider<ResourceSet> resourceSetProvider;
    
    /**
     * Injected resource validator.
     */
    @Inject
    private IResourceValidator validator;
    
    /**
     * Injected code generator.
     */
    @Inject
    private GeneratorDelegate generator;
    
    /**
     * Injected file access object.
     */
    @Inject
    private JavaIoFileSystemAccess fileAccess;
    
    /**
     * Print a fatal error message prefixed with a header that indicates the
     * source and severity.
     * 
     * @param message The message to print.
     */
    public static void printFatalError(String message) {
        System.err.println(HEADER + redAndBold("fatal error: ") + message);
    }
    
    /**
     * Print an error message prefixed with a header that indicates the source 
     * and severity.
     * 
     * @param message The message to print.
     */
    public static void printError(String message) {
        System.err.println(HEADER + redAndBold("error: ") + message);
    }
    
    /**
     * Print an informational message prefixed with a header that indicates the
     * source and severity.
     * 
     * @param message The message to print.
     */
    public static void printInfo(String message) {
        System.out.println(HEADER + bold("info: ") + message);
    }
    
    /**
     * Print a warning message prefixed with a header that indicates the
     * source and severity.
     * 
     * @param message The message to print.
     */
    public static void printWarning(String message) {
        System.out.println(HEADER + bold("warning: ") + message);
    }
    
    /**
     * Return the given string in bold face.
     * 
     * @param s String to type set.
     * @return a bold face version of the given string.
     */
    public static String bold(String s) {
        return BOLD + s + END_BOLD;
    }
    
    /**
     * Return the given string in red color and bold face.
     * 
     * @param s String to type set.
     * @return a red and bold face version of the given string.
     */
    public static String redAndBold(String s) {
        return RED_BOLD + s + END_RED_BOLD;
    }
    
    /**
     * Supported CLI options.
     * 
     * Stores an Apache Commons CLI Option for each entry, sets it to be
     * if required if so specified, and stores whether or not to pass the
     * option to the code generator.
     * 
     * @author Marten Lohstroh <marten@berkeley.edu>
     */
    enum CLIOption {
        COMPILER("c", "target-compiler", true, false, "Target compuler to invoke.", true),
        HELP("h", "help", true, false, "Display this information.", false),
        NO_COMPILE("n", "no-compile", false, false, "Do not invoke target compiler.", true),
        REBUILD("r", "rebuild", false, false, "Rebuild the compiler first.", false),
        UPDATE("u", "update-deps", false, false, "Update dependencies and rebuild the compiler (requires Internet connection).", false),
        FEDERATED("f", "federated", false, false, "Treat main reactor as federated.", false),
        THREADS("t", "threads", false, false, "Specify the default number of threads.", true),
        OUTPUT_PATH("o", "output-path", true, false, "Specify the root output directory.", false);
        
        /**
         * The corresponding Apache CLI Option object.
         */
        public final Option option;
        
        /**
         * Whether or not to pass this option to the code generator.
         */
        public final boolean passOn;
        
        /**
         * Construct a new CLIOption.
         * 
         * @param opt         The short option name. E.g.: "f" denotes a flag
         *                    "-f".
         * @param longOpt     The long option name. E.g.: "foo" denotes a flag
         *                    "--foo".
         * @param hasArg      Whether or not this option has an argument. E.g.:
         *                    "--foo bar" where "bar" is the argument value.
         * @param isReq       Whether or not this option is required. If it is
         *                    required but not specified a menu is shown.
         * @param description The description used in the menu.
         * @param passOn      Whether or not to pass this option as a property
         *                    to the code generator.
         */
        CLIOption(String opt, String longOpt, boolean hasArg, boolean isReq, String description, boolean passOn) {
            this.option = new Option(opt, longOpt, hasArg, description);
            option.setRequired(isReq);
            this.passOn = passOn;
        }
    
        /**
         * Create an Apache Commons CLI Options object and add all the options.
         * 
         * @return Options object that includes all the options in this enum.
         */
        public static Options getOptions() {
            Options opts = new Options();
            Arrays.asList(CLIOption.values()).forEach(o -> opts.addOption(o.option));
            return opts;
        }
        
        /**
         * Return a list of options that are to be passed on to the code
         * generator.
         * 
         * @return List of options that must be passed on to the code gen stage.
         */
        public static List<Option> getPassedOptions() {
            return Arrays.asList(CLIOption.values()).stream()
                    .filter(opt -> opt.passOn).map(opt -> opt.option)
                    .collect(Collectors.toList());
        }
        
    }

    /**
     * Indicate whether or not a rebuild and library update must occur.
     * @return whether or not the update flag is present.
     */
    private boolean mustUpdate() {
        if (cmd.hasOption(CLIOption.UPDATE.option.getOpt())) {
            return true;
        }
        return false;
    }
    
    /**
     * Indicate whether or not a rebuild must occur.
     * @return whether or not the rebuild or update flag is present.
     */
    private boolean mustRebuild() {
        if (mustUpdate() || cmd.hasOption(CLIOption.REBUILD.option.getOpt())) {
            return true;
        }
        return false;
    }
    
    /**
     * 
     * @param args
     */
    public static void main(final String[] args) {
        final Injector injector = new LinguaFrancaStandaloneSetup()
                .createInjectorAndDoEMFRegistration();
        final Main main = injector.<Main>getInstance(Main.class);

        Options options = CLIOption.getOptions();

        CommandLineParser parser = new DefaultParser();
        HelpFormatter formatter = new HelpFormatter();
        
        try {
            main.cmd = parser.parse(options, args);
            
            // If the rebuild flag is not used, or if it is used but the jar
            // is not out of date, continue with the normal flow of execution.
            if (!main.mustRebuild() || (main.mustRebuild() && !main.rebuildAndFork())) {
                List<String> files = main.cmd.getArgList();
                
                if (files.size() < 1) {
                    printFatalError("No input files.");
                    System.exit(1);
                }
                try {
                    main.runGenerator(files);
                } catch (RuntimeException e) {
                    printFatalError("An unexpected error occurred.");
                    System.exit(1);
                }
            }
        } catch (ParseException e) {
            printFatalError("Unable to parse commandline arguments. Reason:");
            System.err.println(e.getMessage());
            formatter.printHelp("lfc", options);
            System.exit(1);
        }
    }
    
    /**
     * 
     * @param cmd
     */
    private void forkAndWait(CommandLine cmd) {
        LinkedList<String> cmdList = new LinkedList<String>();
        cmdList.add("java");
        cmdList.add("-jar");
        cmdList.add(JAR_PATH);
        for (Option o : cmd.getOptions()) {
            if (!CLIOption.REBUILD.option.equals(o)
                    && !CLIOption.UPDATE.option.equals(o)) {
                // Prevent infinite loop when the source fails to compile.
                cmdList.add(o.getOpt() + " " + o.getValue());
            }
        }
        cmdList.addAll(cmd.getArgList());
        Process p;
        try {
            p = new ProcessBuilder(cmdList).inheritIO().start();
            p.waitFor();
        } catch (IOException e) {
            printFatalError("Unable to fork off child process. Reason:");
            System.err.println(e.getMessage());
        } catch (InterruptedException e) {
            printError("Child process was interupted. Exiting.");
        }
        
    }
    
    /**
     * Indicate whether there is any work to do
     * @return
     */
    private boolean needsUpdate() {
        File jar = new File(JAR_PATH);
        long mod = jar.lastModified();
        boolean outOfDate = false;
        try {
            outOfDate = (!jar.exists() || Files
                    .find(Paths.get(SRC_PATH), Integer.MAX_VALUE,
                            (path, attr) -> (attr.lastModifiedTime()
                                    .compareTo(FileTime.fromMillis(mod)) > 0))
                    .count() > 0);

        } catch (IOException e) {
            printFatalError("Rebuild unsuccessful. Reason:");
            System.err.println(e.getMessage());
            System.exit(1);
        }
        return outOfDate;
    }
    
    private void rebuildOrExit() {
        String root = JAR_PATH.replace(JAR_PATH_IN_SRC_TREE, "");
        ProcessBuilder build;
        if (this.mustUpdate()) // FIXME: Use .bat for Windows?
            build = new ProcessBuilder("./gradlew",
                "generateStandaloneCompiler");
        else {
            build = new ProcessBuilder("./gradlew",
                    "generateStandaloneCompiler", "--offline");
        }
        build.directory(new File(root));
    
        try {
            Process p = build.start();
            String result = new String(p.getInputStream().readAllBytes());
            p.waitFor();
            if (p.exitValue() == 0) {
                printInfo("Rebuild successful; forking off updated version.");
            } else {
                printFatalError("Rebuild failed. Reason:");
                System.err.print(result);
                System.exit(1);
            }
        } catch (Exception e) {
            printFatalError("Rebuild failed. Reason:");
            System.err.println(e.getMessage());
            System.exit(1);
        }
    }
    
    private boolean rebuildAndFork() {
        // jar:file:<root>org.icyphy.linguafranca/build/libs/org.icyphy.linguafranca-1.0.0-SNAPSHOT-all.jar!/org/icyphy/generator/Main.class
        if (needsUpdate()) {
            // Only rebuild if the jar is out-of-date.
            printInfo("Jar file is missing or out-of-date; running Gradle.");
            rebuildOrExit();
            forkAndWait(cmd);
        } else {
            printInfo("Not rebuilding; already up-to-date.");
            return false;
        }
        return true;
    }
  
    /**
     * Store arguments as properties, to be passed on to the generator.
     */
    protected Properties getProps(CommandLine cmd) {
        Properties props = new Properties();
        List<Option> passOn = CLIOption.getPassedOptions();
        for (Option o : cmd.getOptions()) {
            if (passOn.contains(o)) {
                String value = "";
                if (o.hasArgs()) {
                    value = o.getValue();
                }
                props.setProperty(o.getLongOpt(), value);
            }
        }
        return props;
    }
  
    private static String joinPaths(String path1, String path2) {
        if (path1.isEmpty()) {
            return path2;
        }
        if (path2.isEmpty()) {
            return path1;
        }
        if (path1.endsWith(File.separator)) {
            if (path2.startsWith(File.separator)) {
                return path1 + path2.substring(1, path2.length());
            } else {
                return path1 + path2;
            }
        } else {
            if (path2.startsWith(File.separator)) {
                return path1 + path2;
            } else {
                return path1 + File.separator + path2;
            }
        }
    }
    
    private static String packageRoot(String file) {
        File f = new File(file).getAbsoluteFile(); 
        String p;
        do {
            p = f.getParent();
            if (p == null) {
                printWarning("File '" + file + "' is not located in an 'src' directory.");
                printInfo("Using the current working directory as output directory.");
                return new File("").getAbsolutePath();
            } else {
                f = new File(p);
            }
        } while (!f.getName().equals("src"));
        return new File(f.getParent()).getAbsolutePath();
    }
    
    /**
     * Load the resource, validate it, and, invoke the code generator.
     */
    protected void runGenerator(List<String> files) {
        Properties properties = this.getProps(cmd);
        String rootPath = "";
        String pathOption = CLIOption.OUTPUT_PATH.option.getOpt();
        if (cmd.hasOption(pathOption)) {
            File root = new File(cmd.getOptionValue(pathOption));
            if (!root.exists()) {
                printFatalError("Output location '" + root + "' does not exist.");
                System.exit(1);
            }
            if (!root.isDirectory()) {
                printFatalError("Output location '" + root + "' is not a directory.");
                System.exit(1);
            }
            try {
                rootPath = root.getCanonicalPath();
            } catch (IOException e) {
                printFatalError("Could not access '" + root + "'.");
            }
        }
        
        for (String file : files) {
            final File f = new File(file);
            if (!f.exists()) {
                printFatalError(
                        file.toString() + ": No such file or directory");
                System.exit(1);
            }
        }
        for (String file : files) {
            final File f = new File(file);
            if (!rootPath.isEmpty()) {
                this.fileAccess.setOutputPath(joinPaths(rootPath, "src-gen"));
            } else {
                this.fileAccess.setOutputPath(joinPaths(packageRoot(file), "src-gen"));
            }
            
            final ResourceSet set = this.resourceSetProvider.get();
            final Resource resource = set
                    .getResource(URI.createFileURI(f.getAbsolutePath()), true);
            
            if (cmd.hasOption(CLIOption.FEDERATED.option.getOpt())) {
                if (!ASTUtils.makeFederated(resource)) {
                    printError("Unable to change main reactor to federated reactor.");
                }
            }
            
            final List<Issue> issues = this.validator.validate(resource,
                    CheckMode.ALL, CancelIndicator.NullImpl);
            if (!issues.isEmpty()) {
                printFatalError("Unable to validate resource. Reason:");
                issues.forEach(issue -> System.err.println(issue));
                System.exit(1);
            }
            
            StandaloneContext _standaloneContext = new StandaloneContext();
            final Procedure1<StandaloneContext> _function_1 = (
                    StandaloneContext it) -> {
                it.setCancelIndicator(CancelIndicator.NullImpl);
                it.setArgs(properties);
            };
            final StandaloneContext context = ObjectExtensions
                    .<StandaloneContext>operator_doubleArrow(_standaloneContext,
                            _function_1);
            this.generator.generate(resource, this.fileAccess, context);
            System.out.println("Code generation finished.");
        }
    }
}