//////////////////////////////////////////////////////////////////////////////
// Tycho Game Library
// Copyright (C) 2014 Martin Slater
// Created : Tuesday, 02 September 2014 06:59:40 PM
//////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////
// INCLUDES
//////////////////////////////////////////////////////////////////////////////
#include "slang/slang.h"
#include "slang/printing/print.h"
#include "slang/printing/print_ast_html.h"
#include "slang/printing/pretty_print.h"
#include "slang/compiler/front_end.h"
#include "slang/compiler/program.h"
#include "consoleapp/console_app.h"
#include "core/printing/text/console_formatter.h"
#include "core/timer.h"
#include "boost/program_options.hpp"
#include "boost/filesystem.hpp"
#include <iostream>
#include <sstream>
#include <fstream>

#if TYCHO_PC
#include "core/pc/safe_windows.h"
#endif

using namespace tycho::slang::compiler;
using namespace tycho::slang;
using namespace tycho;

namespace po = boost::program_options;
namespace fs = boost::filesystem;

//--------------------------------------------------------------------

struct tests
{
	struct test_case
	{
		std::string text;
		size_t	    line; // line in source file this test case was defined at
	};
	;
	std::vector<test_case> test_cases;
	std::string			   source_file;
};

//--------------------------------------------------------------------

class slang_app : public core::console_app_interface
{
public:
	slang_app();
	
	// console_app_interface
	void register_options(core::console_app_options&);
	int  run(boost::program_options::variables_map&);	
	
private:
	bool parse_test_file(const char *file, tests &output);
	bool run_tests(tests tcs, bool check_for_success);
	tycho::slang::compiler::program* run_test(const tests::test_case &tc);
	tycho::slang::compiler::program* run_test_seh(const tests::test_case &tc);
	int get_compile_flags();
	
	
private:
	bool m_test_success;
	bool m_test_failures;
	bool m_trace_ast;
	bool m_trace_ast_html;	
	bool m_trace_parser;
	bool m_trace_symbols;
	int	 m_output_width;
	bool m_pretty_print;
	bool m_trace_internal;
	std::string m_input_file;
    core::printing::text::console_formatter m_console;	
};

//--------------------------------------------------------------------


slang_app::slang_app() :
	m_test_success(false),
	m_test_failures(false),
	m_trace_ast(false),
	m_trace_parser(false),
	m_trace_symbols(false),
	m_pretty_print(false),
	m_trace_internal(false)
{
}

//--------------------------------------------------------------------

void slang_app::register_options(core::console_app_options &options)
{
	// process command line
	po::options_description global_options;
	po::options_description visible_options;

	// run options
	po::options_description main_options("Main Options");
	main_options.add_options()
		("input_file,f",
			po::value(&m_input_file),
			"Input source file");
				
	po::options_description formatting_options("Formatting Options");
	formatting_options.add_options()
		("format.output_width,O",
			po::value(&m_output_width)->default_value(0),
			"Width to format output to, 0 uses current console size")
		("format.print",
			po::bool_switch(&m_pretty_print)->default_value(false),
			"Pretty print resulting program to console");
					
	po::options_description test_options("Test Options");
	test_options.add_options()
		("test.success",		 
			po::bool_switch(&m_test_success)->default_value(false),
			"Run in test mode, input file is a test definition file specifying snippets that should compile")
		("test.failure",
			po::bool_switch(&m_test_failures)->default_value(false),
			"Run in test mode, input file is a test definition file specifying snippets that should NOT compile");
					
	po::options_description debug_options("Debug Options");
	debug_options.add_options()
		("debug.trace_ast,a",	 
			po::bool_switch(&m_trace_ast)->default_value(false),
			"Print an ast trace")
		("debug.trace_ast_html,h",
			po::bool_switch(&m_trace_ast_html)->default_value(false),
			"Output ast trace as a html document to hlsl_debug_ast.html")
		("debug.trace_parser,p", 
			po::bool_switch(&m_trace_parser)->default_value(false),
			"Print a trace of the parser")
		("debug.trace_symbols,s",
			po::bool_switch(&m_trace_symbols)->default_value(false),
			"Print full symbol table after parsing");
			
	options.global.add(main_options);
	options.global.add(formatting_options);
	options.global.add(test_options);
	options.global.add(debug_options);
		
		
	options.positional.add("input_file", -1);
}

//--------------------------------------------------------------------

int slang_app::run(boost::program_options::variables_map &)
{
	m_console.set_tab_size(4);
	m_console.set_page_width(m_output_width);
	
	if(m_test_success || m_test_failures)
	{
		// in test mode set asserts to report via exception
		core::set_assert_handler(core::assert_handler_exception);

		tests test_cases;
		if(!parse_test_file(m_input_file.c_str(), test_cases))
		{
			std::cerr << "Error parsing test case file\n";
			return EXIT_FAILURE;
		}
		if(run_tests(test_cases, !m_test_failures))
			return EXIT_SUCCESS;
			
		return EXIT_FAILURE;
	}
	else
	{
        core::timer timer;
		timer.start();
		fs::path full_path = fs::system_complete(m_input_file);
		std::ifstream istr(full_path.string().c_str());		
		if(!istr)
		{
			std::cerr << "Failed to open input file : " << full_path.string() << "\n";
			return EXIT_FAILURE;
		}
		compiler::front_end front_end;
		compiler::program *program = front_end.compile_file(
			m_input_file.c_str(), 
			compiler::lang_hlsl_dx10, 
			"", 
			get_compile_flags());
			
		double compile_time = timer.elapsed_time();
		if(!program)
		{
			m_console.write("fatal error compiling, exiting\n");
			return EXIT_FAILURE;
		}		
		
		// display messages added during compilation
		program->print(&m_console);					
		m_console.horizontal_bar(0);
		m_console.format("%d error(s), %d warning(s) in %.3f seconds\n", 
			program->get_message_count(mt_error), program->get_message_count(mt_warning), compile_time);
		m_console.newline();
		if(program->get_message_count(mt_internal))
			m_console.format("!!! Contains internal compiler errors\n");
		program->get_allocator()->print_usage_stats(&m_console);		
		m_console.horizontal_bar(0);
				
		if(m_trace_ast && program->get_ast())
			printing::print_tree(*program->get_ast());
		if(m_trace_ast_html)
			printing::print_ast_html(program, "hlsl_debug_ast.html");
		if(m_pretty_print && program->get_ast())
			printing::pretty_printer().format(*program->get_ast(), m_console);		
		if(m_trace_symbols)
			program->get_symbol_table()->print(&m_console, m_trace_internal);
			
		return program->is_valid() ? EXIT_SUCCESS : EXIT_FAILURE;
	}
	
	return EXIT_SUCCESS;
}

//--------------------------------------------------------------------

bool slang_app::parse_test_file(const char *file, tests &output)
{
	FILE *f = fopen(file, "rt");
	if(!f)
		return false;
	output.source_file = file;
	fseek(f, 0L, SEEK_END);
	long size = ftell(f);
	fseek(f, 0L, SEEK_SET);
	std::vector<char> text(size, 0);
	fread(&text[0], size, 1, f);
	fclose(f);
	std::string s(&text[0]);
	size_t p;
	size_t op = 0;
	size_t line = 0;
	while((p = s.find(std::string("//--"), op)) != std::string::npos)
	{
		// count line breaks up to here
		for(size_t i = op; i < p; ++i)
			if(s[i] == '\n')
				++line;

		tests::test_case tc;
		tc.text = s.substr(op, p-op);
		tc.line = line;
		output.test_cases.push_back(tc);
		op = p + 4;
	}
	return true;
}

//--------------------------------------------------------------------

int slang_app::get_compile_flags()
{
	int compile_flags = 0;
	if(m_trace_symbols) compile_flags |= comp_trace_symbols; 
	if(m_trace_ast)		compile_flags |= comp_trace_ast;
	if(m_trace_parser)	compile_flags |= comp_trace_parser;
	return compile_flags;
}

//--------------------------------------------------------------------

int ExceptionHandler(int code, PEXCEPTION_POINTERS context, const char *cppExceptionInfo)
{
	return EXCEPTION_EXECUTE_HANDLER;
}

//--------------------------------------------------------------------

compiler::program* slang_app::run_test(const tests::test_case &tc)
{
	// catch and report assert exception
	try
	{
		int compile_flags = get_compile_flags();
		bool trace = compile_flags != 0;
		compiler::front_end front_end;
		return front_end.compile_string(tc.text.c_str(), compiler::lang_hlsl_dx10, "", compile_flags);
	}
	catch (const core::assert_exception &ex)
	{
        m_console.format("%s(%d) : assert : %s\n", ex.file, ex.line, ex.msg);
	}
	return 0;
}

//--------------------------------------------------------------------

compiler::program* slang_app::run_test_seh(const tests::test_case &tc)
{
	const int ExceptionInfoLen = 1024;
    char exceptionInfo[ExceptionInfoLen+3];  // \r\n\0
	__try
	{
		return run_test(tc);
	}
	__except(ExceptionHandler(0, GetExceptionInformation(), exceptionInfo))
	{
		return 0;
	}
}

//--------------------------------------------------------------------

bool slang_app::run_tests(tests tcs, bool check_for_success)
{
	std::vector<tests::test_case*> failures;
	int num_failed = 0, num_succeeded = 0;
	std::string output;
	for(size_t i = 0; i < tcs.test_cases.size(); ++i)
	{
		const tests::test_case &tc = tcs.test_cases[i];
		compiler::program* program = run_test_seh(tc);
		bool ok = program && program->is_valid();
		if(!check_for_success)
			ok = !ok;

		if(!ok)
		{
			m_console.format("%s(%d) : error :", tcs.source_file.c_str(), tc.line);
			m_console.inc_indent();
			if(program)
				program->print(&m_console);
			else
				m_console.writeln(" internal : compiler crash");
			m_console.format("\n%s", tc.text.c_str());
			m_console.dec_indent();
			++num_failed;
		}
		else
		{
			++num_succeeded;
		}	

// 		if(trace)
// 			break;
	}
	
	bool success = num_failed == 0;
	
	if(m_test_failures)
		std::swap(num_failed, num_succeeded);

	std::cout << "-----------------------------------------------\n";
	printf("%s : %d Passed and %d Failed compilation\n", (success ? "Success" : "Error"), num_succeeded, num_failed);
	std::cout << "-----------------------------------------------\n";
	std::cout << output.c_str() << "\n";;
	
	// write results to report file
	fs::path test_report_file = boost::filesystem::change_extension(m_input_file, ".report.html");	
	std::ofstream report_file(test_report_file.string().c_str());
	if(report_file)
	{
		report_file << "foo\n";
		report_file.close();
	}
	else
	{		
		std::cout << "Unable to open test report file : " << test_report_file << "\n";
	}
	
	return success;
}

//--------------------------------------------------------------------

#if TYCHO_PC
int wmain(int argc, wchar_t* argv[])
#else
int main(int argc, char* argv)
#endif
{
    return tycho::core::console_app::main<slang_app>(
		"slang.exe",
        "--------------------------------------------------------------\n"
		"slang\n"
        "--------------------------------------------------------------\n"
        "Tool description goes here",
		argc, argv);
}

//--------------------------------------------------------------------
