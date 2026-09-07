$ErrorActionPreference = "Stop"

$TestRef = "krejepenqgcmnsugbpmv"
$Cert = $PSScriptRoot

Set-Location $Cert

$Candidates = @(
    (Join-Path $Cert "supabase\.temp\project-ref"),
    (Join-Path $Cert ".supabase\project-ref")
)

$LinkedRef = $null

foreach ($Candidate in $Candidates) {
    if (Test-Path $Candidate) {
        $LinkedRef = (
            Get-Content $Candidate -Raw
        ).Trim()
        break
    }
}

if ([string]::IsNullOrWhiteSpace($LinkedRef)) {
    throw "Cannot determine linked Supabase project."
}

if ($LinkedRef -ne $TestRef) {
    throw "STOP: Reset blocked. This script runs ONLY against THQ-ERP-MIGRATION-TEST."
}

Write-Host "TEST project verified: $LinkedRef"

$DropSql = @"
DROP SEQUENCE IF EXISTS public.business_division_code_seq;
DROP SEQUENCE IF EXISTS public.cashier_shift_number_seq;
DROP SEQUENCE IF EXISTS public.customer_receipt_number_seq;
DROP SEQUENCE IF EXISTS public.finance_voucher_number_seq_v500;
DROP SEQUENCE IF EXISTS public.goods_receipt_number_seq_v484;
DROP SEQUENCE IF EXISTS public.journal_entry_number_seq;
DROP SEQUENCE IF EXISTS public.loan_number_seq_v490;
DROP SEQUENCE IF EXISTS public.loan_payment_number_seq_v490;
DROP SEQUENCE IF EXISTS public.pos_hold_code_seq;
DROP SEQUENCE IF EXISTS public.purchase_invoice_number_seq_v484;
DROP SEQUENCE IF EXISTS public.purchase_order_number_seq;
DROP SEQUENCE IF EXISTS public.purchase_quotation_number_seq_v500;
DROP SEQUENCE IF EXISTS public.purchase_request_number_seq_v484;
DROP SEQUENCE IF EXISTS public.purchase_return_number_seq;
DROP SEQUENCE IF EXISTS public.sales_return_number_seq;
DROP SEQUENCE IF EXISTS public.stock_count_number_seq;
DROP SEQUENCE IF EXISTS public.stock_transfer_number_seq;
DROP SEQUENCE IF EXISTS public.supplier_payment_number_seq_v484;
DROP SEQUENCE IF EXISTS public.support_ticket_number_seq;
DROP SEQUENCE IF EXISTS public.workshop_job_number_seq;
"@

supabase db query $DropSql --linked

if ($LASTEXITCODE -ne 0) {
    throw "Failed to remove TEST reset sequence residue."
}

Write-Host ""
Write-Host "Sequence residue removed."
Write-Host "Starting TEST reset..."

supabase db reset --linked

if ($LASTEXITCODE -ne 0) {
    throw "TEST reset failed."
}

Write-Host ""
Write-Host "THQ TEST reset completed safely."
