Analyze the Pester test files for the dbatools PowerShell module and perform the following migration tasks from Pester v4 to v5:

1. Move all test code into appropriate blocks:
   - Relocate any code outside of `It`, `BeforeAll`, `BeforeEach`, `AfterAll`, or `AfterEach` blocks into the correct locations.
   - Place file setup code into `BeforeAll` blocks at the beginning of each test file.

2. Update `Describe` and `Context` blocks:
   - Remove any test code directly in these blocks.
   - Ensure proper nesting of `Context` within `Describe`.

3. Refactor `Skip` conditions:
   - Move skip logic outside of `BeforeAll` blocks.
   - Use global read-only variables for skip conditions where appropriate.

4. Update `TestCases`:
   - Ensure TestCases are defined in a way that's compatible with Pester v5's discovery phase.

5. Update assertion syntax:
   - Replace `Should Be` with `Should -Be`.
   - Update other assertion operators as needed (e.g., `Should Throw` to `Should -Throw`).

6. Modify `InModuleScope` usage:
   - Remove `InModuleScope` from around `Describe` and `It` blocks.
   - Replace with `-ModuleName` parameter on `Mock` where possible.

7. Update `Invoke-Pester` calls:
   - Modify parameters to align with Pester v5's simple or advanced interface.

8. Adjust mocking syntax:
   - Update any mock definitions to Pester v5 syntax.

9. Analyze and update: /workspace/tests/--CMDNAME--.Tests.ps1

Make these changes directly in the code. If you encounter any SQL Server-specific testing scenarios that require special handling, implement the necessary adjustments while maintaining the integrity of the tests.