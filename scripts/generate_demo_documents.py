from fpdf import FPDF
import textwrap, os

os.makedirs(r"C:\Users\rakes\borrower360\documents", exist_ok=True)

def make_pdf(title, body, filename):
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 14)
    pdf.multi_cell(0, 10, title)
    pdf.ln(4)
    pdf.set_font("Courier", "", 8)
    for line in body.split("\n"):
        if line.strip() == "":
            pdf.ln(5)
        else:
            pdf.multi_cell(0, 5, line)
        pdf.set_x(pdf.l_margin)
    pdf.output(rf"C:\Users\rakes\borrower360\documents\{filename}")
    print(f"wrote {filename}")

salary_slip = """Self-Employed Consulting Income Statement
Issued by: A. R. Menon & Co, Chartered Accountants
Registration No: FRN-004521S

Name: Deepak Kumar
PAN: AABPN1234F
Month: July 2026

Gross Professional Fees:        Rs 50,000
Less: TDS Deducted @ 10%:       Rs  5,000
Net Income Before Deductions:   Rs 45,000
Less: Professional Tax @ 3%:    Rs  1,350
Net Amount Paid:                Rs 43,650
"""

bank_statement = """Bank Statement Excerpt - July 2026
Account Holder: Deepak Kumar

Date         Description                Debit(Rs)   Credit(Rs)   Balance(Rs)
01-Jul-2026  Opening Balance            0           50,000       50,000
10-Jul-2026  Consulting Fee - Client A  0           22,300       72,300
15-Jul-2026  Consulting Fee - Client B  0           22,300       94,600
20-Jul-2026  Electricity Bill           1,500       0            93,100
25-Jul-2026  Groceries                  2,000       0            91,100
28-Jul-2026  EMI - Arthaa Finance       21,506      0            69,594
31-Jul-2026  Closing Balance            -           -            69,594
"""

hardship_letter = """Subject: Temporary Cash Flow Issue - Request for Part-Payment Arrangement

Dear Arthaa Finance Team,

I hope this message finds you well. I wanted to bring to your attention a
recent development that has temporarily strained my cash flow. One of my
clients, a significant contributor to my business revenue, has experienced
unforeseen financial difficulties resulting in a delayed payment this
month.

I understand the importance of meeting my loan obligations and I am
committed to doing so. However, this unexpected situation has left me with
a short-term liquidity challenge. I believe we can work together to find a
mutually beneficial solution.

I kindly request your assistance in arranging a brief part-payment
arrangement for this month. I am confident my business will recover and I
will resume regular payments as soon as possible.

Thank you for your consideration.

Best regards,
Deepak Kumar
Self-Employed Borrower
"""

make_pdf("Salary Slip - Deepak Kumar", salary_slip, "salary_slip_deepak_kumar.pdf")
make_pdf("Bank Statement - Deepak Kumar", bank_statement, "bank_statement_deepak_kumar.pdf")
make_pdf("Hardship Letter - Deepak Kumar", hardship_letter, "hardship_letter_deepak_kumar.pdf")
