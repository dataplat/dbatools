# Tasks - Break Specification into Actionable Items

Generate a list of small, reviewable, testable tasks from a dbatools specification.

## Input Required

**Specification File**: --SPECFILE--
**Plan File**: --PLANFILE-- (optional)

## Instructions

Break the specification into discrete tasks that:

1. **Are independently completable** - Each task can be done and reviewed alone
2. **Are testable** - Clear success criteria for each task
3. **Follow logical order** - Dependencies are respected
4. **Are appropriately sized** - Not too large, not too granular

## Task Categories for dbatools Commands

### 1. Setup Tasks
- [ ] Create command file scaffold
- [ ] Add function signature with parameters
- [ ] Add comment-based help structure

### 2. Core Implementation Tasks
- [ ] Implement connection handling
- [ ] Implement main processing loop
- [ ] Implement SMO/T-SQL logic
- [ ] Implement output object creation

### 3. Error Handling Tasks
- [ ] Add Stop-Function for connection failures
- [ ] Add version compatibility checks
- [ ] Add permission/access error handling

### 4. Documentation Tasks
- [ ] Complete comment-based help
- [ ] Add parameter descriptions
- [ ] Add examples (minimum 3)
- [ ] Generate .OUTPUTS documentation

### 5. Test Tasks
- [ ] Create test file scaffold
- [ ] Add parameter validation tests
- [ ] Add unit tests for core functionality
- [ ] Add integration tests

### 6. Registration Tasks
- [ ] Add to dbatools.psd1 FunctionsToExport
- [ ] Add to dbatools.psm1 Export-ModuleMember

## Output Format

```markdown
# Tasks: <Command Name>

## Task List

### Phase 1: Scaffold (Can be parallelized)

- [ ] **Task 1.1**: Create command file `public/<Command>.ps1`
  - Create file with basic structure
  - Add function declaration
  - Success: File exists with valid PowerShell syntax

- [ ] **Task 1.2**: Create test file `tests/<Command>.Tests.ps1`
  - Create Pester v5 test scaffold
  - Success: File exists with Describe block

### Phase 2: Parameters

- [ ] **Task 2.1**: Add standard parameters
  - SqlInstance, SqlCredential, EnableException
  - Use correct types (DbaInstanceParameter[], PSCredential, Switch)
  - Success: Parameters defined without `= $true` syntax

- [ ] **Task 2.2**: Add command-specific parameters
  - <List parameters from spec>
  - Success: All spec parameters present with correct types

### Phase 3: Core Logic

- [ ] **Task 3.1**: Implement connection handling
  - Use Connect-DbaInstance pattern
  - Add try/catch with Stop-Function
  - Success: Connects to test instance without error

- [ ] **Task 3.2**: Implement main functionality
  - <Describe core logic>
  - Success: <Define success criteria>

- [ ] **Task 3.3**: Implement output emission
  - Create PSCustomObject with required properties
  - Emit immediately in foreach loop
  - Success: Objects emit to pipeline correctly

### Phase 4: Error Handling

- [ ] **Task 4.1**: Add SQL version check
  - Use MinimumVersion or conditional logic
  - Skip gracefully for unsupported versions
  - Success: Appropriate warning on old SQL versions

- [ ] **Task 4.2**: Add error handling for <specific scenario>
  - <Describe handling>
  - Success: <Define criteria>

### Phase 5: Documentation

- [ ] **Task 5.1**: Complete comment-based help
  - Synopsis, Description, Parameters, Examples
  - Minimum 3 examples
  - Success: Get-Help returns complete documentation

- [ ] **Task 5.2**: Add .OUTPUTS documentation
  - Use typesncolumns.md prompt
  - Success: Output type documented

### Phase 6: Tests

- [ ] **Task 6.1**: Add parameter validation tests
  - Test mandatory parameters
  - Test parameter types
  - Success: Tests pass

- [ ] **Task 6.2**: Add integration tests
  - Test against $TestConfig.instance1
  - Test pipeline scenarios
  - Success: Tests pass on CI

### Phase 7: Registration

- [ ] **Task 7.1**: Register command
  - Add to dbatools.psd1 FunctionsToExport
  - Add to dbatools.psm1 Export-ModuleMember
  - Success: Command exports correctly

## Task Dependencies

```
1.1, 1.2 (parallel)
    ↓
2.1 → 2.2
    ↓
3.1 → 3.2 → 3.3
    ↓
4.1, 4.2 (parallel)
    ↓
5.1 → 5.2
    ↓
6.1 → 6.2
    ↓
7.1
```

## Verification Checklist

After all tasks complete:
- [ ] No backticks in code
- [ ] No `= $true` in attributes
- [ ] No `::new()` syntax
- [ ] Splatting used for 3+ parameters
- [ ] Hashtables aligned
- [ ] Objects emitted immediately
- [ ] All tests pass
```
