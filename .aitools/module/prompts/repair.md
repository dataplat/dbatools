You are fixing ALL the test failures in this file. This test has already been migrated to Pester v5 and styled according to dbatools conventions.

CRITICAL RULES - DO NOT CHANGE THESE:
1. PRESERVE ALL COMMENTS EXACTLY - Every single comment must remain intact
2. Keep ALL Pester v5 structure (BeforeAll/BeforeEach blocks, #Requires header, static CommandName)
3. Keep ALL hashtable alignment - equals signs must stay perfectly aligned
4. Keep ALL variable naming (unique scoped names, $splat<Purpose> format)
5. Keep ALL double quotes for strings
6. Keep ALL existing $PSDefaultParameterValues handling for EnableException
7. Keep ALL current parameter validation patterns with filtering
8. ONLY fix the specific errors - make MINIMAL changes to get tests passing
9. DO NOT CHANGE PSDefaultParameterValues, THIS IS THE NEW WAY $PSDefaultParameterValues = $TestConfig.Defaults

COMMON PESTER v5 SCOPING ISSUES TO CHECK:
- Variables defined in BeforeAll may need $global: to be accessible in It blocks
- Variables shared across Context blocks may need explicit scoping
- Arrays and objects created in setup blocks may need scope declarations
- Test data variables may need $global: prefix for cross-block access

PESTER v5 STRUCTURAL PROBLEMS TO CONSIDER:
If you only see generic failure messages like 'Test failed but no error message could be extracted' or 'Result: Failed' with no ErrorRecord/StackTrace, this indicates Pester v5 architectural issues:
- Mocks defined at script level instead of in BeforeAll{} blocks
- [Parameter()] attributes on test parameters (remove these)
- Variables/functions not accessible during Run phase due to discovery/run separation
- Should -Throw assertions with square brackets or special characters that break pattern matching
- Mock scope issues where mocks aren't available to the functions being tested

HOW TO USE THE REFERENCE TEST:
The reference test (v4) shows the working test logic. Focus on extracting:
- The actual test assertions and expectations
- Variable assignments and test data setup
- Mock placement and scoping patterns
- How variables are shared between test blocks
DO NOT copy the v4 structure - keep all current v5 BeforeAll/Context/It patterns.
Compare how mocks/variables are scoped between the working v4 version and the failing v5 version. The test logic should be identical but the scoping might be wrong.

WHAT YOU CAN CHANGE:
- Fix syntax errors causing the specific failures
- Correct variable scoping issues (add $global: if needed for cross-block variables)
- Move mock definitions from script level into BeforeAll{} blocks
- Remove [Parameter()] attributes from test parameters
- Fix array operations ($results.Count → $results.Status.Count if needed)
- Correct boolean skip conditions
- Fix Where-Object syntax if causing errors
- Adjust assertion syntax if failing
- Escape special characters in Should -Throw patterns or use wildcards
- If you see variables or mocks that work in the v4 version but are out of scope in v5, you MAY add $global: prefixes or move definitions into appropriate blocks

REFERENCE (DEVELOPMENT BRANCH):
The working version is provided for comparison of test logic only. Do NOT copy its structure - it may be older Pester v4 format without our current styling. Use it only to understand what the test SHOULD accomplish.
TASK - Make the minimal code changes necessary to fix ALL the failures above while preserving all existing Pester v5 migration work and dbatools styling conventions.

MIGRATION AND STYLE REQUIREMENTS:
The following migration and style guides MUST be followed exactly.

ALL FAILURES TO FIX IN THIS FILE: