@{
    # Business Central container used to publish and run tests
    ContainerName        = 'BC28-DK'
    # Credentials are read from the environment, never stored here:
    #   $env:BC_USERNAME, $env:BC_PASSWORD
    Tenant               = 'default'

    # Folder (relative to repo root) that contains the AL app under test (app.json) and the test app.
    # Single-app layout: both are the same folder.
    AppFolder            = '.'

    # Correction budget per phase (K in the thesis). Must be identical for the baseline.
    MaxCorrectionRounds  = 3

    # Run the REFACTOR phase after GREEN. $true/$false, identical for all runs of an experiment.
    # The green code is snapshotted first and the refactoring is shown as a diff (.tdd\<Req>.refactor.diff).
    RunRefactor          = $true

    # Model used for experiment runs
    Model                = 'claude-sonnet-5-5'

    # alc.exe is auto-detected from the newest installed AL VS Code extension; set to override.
    AlcPath              = ''
}
