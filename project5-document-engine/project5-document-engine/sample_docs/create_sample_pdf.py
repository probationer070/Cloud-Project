#!/usr/bin/env python3
"""
테스트용 샘플 PDF 생성 스크립트
실행: python3 create_sample_pdf.py
의존성: pip install reportlab
"""

try:
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfgen import canvas

    def create_sample_pdf(filename="sample.pdf"):
        c = canvas.Canvas(filename, pagesize=A4)
        width, height = A4

        c.setFont("Helvetica-Bold", 18)
        c.drawString(50, height - 60, "Cloud Portfolio - Q4 Financial Report 2024")

        c.setFont("Helvetica", 12)
        content = [
            "",
            "Executive Summary",
            "─" * 60,
            "The fourth quarter revenue reached 2 million USD, representing",
            "a 35% year-over-year growth compared to Q4 2023.",
            "",
            "Key Highlights",
            "─" * 60,
            "- Q4 Revenue: $2,000,000 (target was $1,800,000)",
            "- Annual recurring revenue grew by 42%",
            "- Customer acquisition cost decreased by 18%",
            "- Net Promoter Score improved from 45 to 67",
            "",
            "Cloud Infrastructure Investment",
            "─" * 60,
            "AWS cloud migration reduced operational costs by 31%.",
            "Serverless architecture adoption saved $450,000 annually.",
            "AI-powered customer service reduced support tickets by 28%.",
            "",
            "Document Analysis Engine Impact",
            "─" * 60,
            "The intelligent document processing system handles 10,000+",
            "documents daily with 94% accuracy in data extraction.",
            "Processing time reduced from 2 hours to under 30 seconds.",
            "",
            "Outlook for Q1 2025",
            "─" * 60,
            "Expected revenue growth of 20-25% in the first quarter.",
            "New product launches planned for February and March.",
            "International expansion into Southeast Asian markets.",
        ]

        y = height - 100
        for line in content:
            if y < 50:
                c.showPage()
                y = height - 50
                c.setFont("Helvetica", 12)
            c.drawString(50, y, line)
            y -= 20

        c.save()
        print(f"✅ 샘플 PDF 생성 완료: {filename}")
        print(f"   업로드 명령어: aws s3 cp {filename} s3://[버킷이름]/{filename}")

    create_sample_pdf()

except ImportError:
    # reportlab 없을 때는 텍스트 파일로 대체
    content = """Cloud Portfolio - Q4 Financial Report 2024

Executive Summary
The fourth quarter revenue reached 2 million USD, representing
a 35% year-over-year growth compared to Q4 2023.

Key Highlights
- Q4 Revenue: $2,000,000 (target was $1,800,000)
- Annual recurring revenue grew by 42%
- Customer acquisition cost decreased by 18%
- Net Promoter Score improved from 45 to 67

Cloud Infrastructure Investment
AWS cloud migration reduced operational costs by 31%.
Serverless architecture adoption saved $450,000 annually.
AI-powered customer service reduced support tickets by 28%.

Document Analysis Engine Impact
The intelligent document processing system handles 10,000+
documents daily with 94% accuracy in data extraction.
Processing time reduced from 2 hours to under 30 seconds.

Outlook for Q1 2025
Expected revenue growth of 20-25% in the first quarter.
New product launches planned for February and March.
International expansion into Southeast Asian markets.
"""
    with open("sample.txt", "w") as f:
        f.write(content)
    print("⚠️  reportlab 미설치 — sample.txt 생성됨")
    print("   설치 후 재실행: pip install reportlab")
    print("   또는 직접 PDF를 준비해서 업로드하세요")
