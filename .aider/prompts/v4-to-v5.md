Breaking changes in v5:
- Pester now runs in two phases: Discovery and Run. Put test code in It, BeforeAll, BeforeEach, AfterAll or AfterEach.
- Misplaced code will run during Discovery and results won't be available during Run. Explicitly place discovery code in BeforeDiscovery.
- Move file setup into a BeforeAll block. Avoid using $MyInvocation.MyCommand.Path.
- Be cautious with -Skip:$SomeCondition as skip conditions are evaluated during Discovery. Prefer static global variables or cheap-to-execute code.
- TestCases are evaluated during Discovery. Avoid expensive setup in TestCases.

New result object:
- The new result object is rich and used by Pester internally.
- Use ConvertTo-Pester4Result for compatibility with CI pipelines expecting Pester 4 format.
- Use ConvertTo-NUnitReport or -CI switch for NUnit output, code coverage, and exit code on failure.

Simplified Invoke-Pester interface:
- Simple interface uses individual parameters. Advanced interface takes a PesterConfiguration object.
- Legacy parameters are mapped to configuration object properties.

Scoping in Pester v5:
- More granular approach compared to v4.
- Local: Limited to the immediate block (e.g., It, helper function).
- Script: Accessible within the entire script file, but nested blocks may not inherit this scope automatically like in v4.
- Global: Accessible throughout the entire PowerShell session. Use if script: scope isn't working as expected, but manage carefully to avoid test contamination.
- Variables in BeforeAll and BeforeEach may behave differently in v5. Explicitly declare with global: or refactor tests to initialize them appropriately for access across multiple It blocks or nested contexts.

Other notes:
- Implicit parameters for TestCases to avoid repetitive param blocks.
- Mocks can now be debugged.
- Avoid overusing InModuleScope. Prefer using -ModuleName on Mock.