$ErrorActionPreference = 'Stop'
# Opens a review of the whole staging branch. Does not deploy production.
Start-Process 'https://github.com/thariqmanchara321/THQ-ERP/compare/main...staging?expand=1'
