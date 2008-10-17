/**
 * Handle all the finance details. Since we only have 1 bank account we make
 * this class singular.
 */
class Finance {

	static minimumBankReserve = 7000;
	
	/**
	 * Returns the maximum amount of money that can be spend.
	 */
	function GetMaxMoneyToSpend();
	
	/**
	 * Get the maximum loan.
	 */
	function GetMaxLoan();
	
	/**
	 * Repay as much as possible.
	 */
	function RepayLoan();
}

function Finance::GetMaxMoneyToSpend() {
	return AICompany.GetBankBalance(AICompany.MY_COMPANY) + AICompany.GetMaxLoanAmount() - AICompany.GetLoanAmount() - Finance.minimumBankReserve;
}

function Finance::GetMaxLoan() {
	local loanMode = AIExecMode();
	AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());	
}

function Finance::RepayLoan() {
	local loanMode = AIExecMode();
	local loanInterval = AICompany.GetLoanInterval();
	while (AICompany.GetBankBalance(AICompany.MY_COMPANY) - loanInterval > Finance.minimumBankReserve && AICompany.SetLoanAmount(AICompany.GetLoanAmount() - loanInterval));
}
