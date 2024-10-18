Analyze and update the Pester test file for the dbatools PowerShell module at /workspace/tests/--CMDNAME--.Tests.ps1. Focus on the following:

1. Review the provided errors and their line numbers.
2. ONLY FOR SCOPING ERRORS: We should have used type full names and we used type short names. For any type errors, consult types.md and apply the appropriate replacements. Do not remove any arrays ([]), just replace the type names. Do not replace type names not causing errors.
3. Remember these are primarily INTEGRATION tests. Only mock when absolutely necessary.
4. Make minimal changes required to make the tests pass. Avoid over-engineering.
5. For SQL Server-specific testing scenarios, implement necessary adjustments while preserving test integrity.
6. If you encounter Pester v4 to v5 migration issues, update the test structure accordingly.
7. Refer to the attached files for migration guidance (we may have missed some v4 syntax) as well as scoping guidance.
8. DO NOT replace $global: variables with $script: variables UNLESS you are 100% certain it will solve the given error.
9. DO NOT change the names of variables unless you're 100% certain it will solve the given error.
10. We have a feeling that many of these errors are as a result of scoping issues. Think deeply about scope and how it affects the test.
11. The constants.ps1 file is provided for your reference to better udnerstand the constants used in the tests.

Edit the test and provide a summary of the changes made.

Errors to address: