import io
import logging
from datetime import datetime

from fpdf import FPDF
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.analytics_service import AnalyticsService

logger = logging.getLogger(__name__)


class _ReportPDF(FPDF):
    """Custom FPDF subclass with header/footer branding."""

    def header(self):
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(100, 100, 100)
        self.cell(0, 8, "MediaFlow Health Report", align="L")
        self.ln(10)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "", 8)
        self.set_text_color(150, 150, 150)
        self.cell(0, 10, f"Page {self.page_no()}/{{nb}}", align="C")

    # ── Helpers ────────────────────────────────────────────────────────

    def section_title(self, title: str):
        """Render a bold section header with a subtle underline."""
        self.ln(6)
        self.set_font("Helvetica", "B", 14)
        self.set_text_color(37, 106, 244)  # #256af4
        self.cell(0, 10, title, new_x="LMARGIN", new_y="NEXT")
        # Thin accent line
        self.set_draw_color(37, 106, 244)
        self.set_line_width(0.5)
        self.line(self.l_margin, self.get_y(), self.w - self.r_margin, self.get_y())
        self.ln(4)

    def key_value(self, label: str, value: str):
        """Render a label: value pair on one line."""
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(60, 60, 60)
        self.cell(60, 7, label + ":", new_x="END")
        self.set_font("Helvetica", "", 10)
        self.set_text_color(30, 30, 30)
        self.cell(0, 7, value, new_x="LMARGIN", new_y="NEXT")

    def table_header(self, col_widths: list[float], headers: list[str]):
        """Render a table header row with a dark background."""
        self.set_font("Helvetica", "B", 9)
        self.set_fill_color(37, 106, 244)
        self.set_text_color(255, 255, 255)
        for w, h in zip(col_widths, headers):
            self.cell(w, 8, h, border=0, fill=True, align="C")
        self.ln()

    def table_row(self, col_widths: list[float], values: list[str], fill: bool = False):
        """Render a table data row with optional alternating fill."""
        self.set_font("Helvetica", "", 9)
        self.set_text_color(30, 30, 30)
        if fill:
            self.set_fill_color(240, 244, 255)
        else:
            self.set_fill_color(255, 255, 255)
        for w, v in zip(col_widths, values):
            self.cell(w, 7, v, border=0, fill=True, align="C")
        self.ln()


def _format_bytes(b: int) -> str:
    """Human-readable file size."""
    if b <= 0:
        return "0 B"
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(b) < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PB"


class ReportService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.analytics = AnalyticsService(session)

    async def generate_health_report(self) -> bytes:
        """Generate a comprehensive PDF health report and return the raw bytes."""

        # ── Gather data ────────────────────────────────────────────────
        overview = await self.analytics.get_overview()
        health = await self.analytics.get_health_score()
        codecs = await self.analytics.get_codec_distribution()
        resolutions = await self.analytics.get_resolution_distribution()
        opportunities = await self.analytics.get_top_opportunities()
        server_perf = await self.analytics.get_server_performance()

        # ── Build PDF ──────────────────────────────────────────────────
        pdf = _ReportPDF(orientation="P", unit="mm", format="A4")
        pdf.alias_nb_pages()
        pdf.set_auto_page_break(auto=True, margin=20)
        pdf.add_page()

        # ── Title block ───────────────────────────────────────────────
        pdf.set_font("Helvetica", "B", 24)
        pdf.set_text_color(37, 106, 244)
        pdf.cell(0, 14, "MediaFlow Health Report", new_x="LMARGIN", new_y="NEXT", align="C")
        pdf.set_font("Helvetica", "", 11)
        pdf.set_text_color(120, 120, 120)
        pdf.cell(
            0, 8,
            f"Generated on {datetime.utcnow().strftime('%B %d, %Y at %H:%M UTC')}",
            new_x="LMARGIN", new_y="NEXT", align="C",
        )
        pdf.ln(6)

        # ── 1. Overview ───────────────────────────────────────────────
        pdf.section_title("Overview")
        pdf.key_value("Total Media Items", f"{overview.total_items:,}")
        pdf.key_value("Libraries Synced", str(overview.libraries_synced))
        pdf.key_value("Workers Online", str(overview.workers_online))
        pdf.key_value("Total Media Size", _format_bytes(overview.total_media_size))
        pdf.key_value("Total Savings Achieved", _format_bytes(overview.total_savings_achieved))
        pdf.key_value("Completed Transcodes", f"{overview.completed_transcodes:,}")
        pdf.key_value("Average Compression", f"{overview.avg_compression_ratio:.1%}")

        # ── 2. Health Score ───────────────────────────────────────────
        pdf.section_title("Library Health Score")
        pdf.set_font("Helvetica", "B", 36)
        grade_colors = {
            "A": (34, 197, 94), "B": (102, 204, 77), "C": (245, 158, 11),
            "D": (230, 128, 51), "F": (239, 68, 68),
        }
        r, g, b = grade_colors.get(health.grade, (120, 120, 120))
        pdf.set_text_color(r, g, b)
        pdf.cell(30, 20, health.grade, new_x="END")
        pdf.set_font("Helvetica", "", 14)
        pdf.set_text_color(60, 60, 60)
        pdf.cell(0, 20, f"  Score: {health.score}/100", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(2)

        col_w = [60.0, 40.0]
        pdf.table_header(col_w, ["Metric", "Score"])
        metrics = [
            ("Modern Codecs", f"{health.modern_codec_pct:.1f}%"),
            ("Bitrate Quality", f"{health.bitrate_pct:.1f}%"),
            ("Modern Containers", f"{health.container_pct:.1f}%"),
            ("Audio Efficiency", f"{health.audio_pct:.1f}%"),
        ]
        for i, (label, val) in enumerate(metrics):
            pdf.table_row(col_w, [label, val], fill=(i % 2 == 0))
        pdf.ln(2)

        # ── 3. Codec Distribution ─────────────────────────────────────
        pdf.section_title("Codec Distribution")
        if codecs.codecs:
            col_w = [50.0, 35.0, 45.0]
            pdf.table_header(col_w, ["Codec", "Count", "Total Size"])
            total_count = sum(codecs.counts) or 1
            for i, (codec, count, size) in enumerate(zip(codecs.codecs, codecs.counts, codecs.sizes)):
                pct = count / total_count * 100
                pdf.table_row(
                    col_w,
                    [codec.upper(), f"{count:,} ({pct:.0f}%)", _format_bytes(size)],
                    fill=(i % 2 == 0),
                )
        else:
            pdf.set_font("Helvetica", "I", 10)
            pdf.set_text_color(150, 150, 150)
            pdf.cell(0, 8, "No codec data available.", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(2)

        # ── 4. Resolution Breakdown ──────────────────────────────────
        pdf.section_title("Resolution Breakdown")
        if resolutions.resolutions:
            col_w = [50.0, 35.0, 45.0]
            pdf.table_header(col_w, ["Resolution", "Count", "Total Size"])
            total_count = sum(resolutions.counts) or 1
            for i, (res, count, size) in enumerate(zip(resolutions.resolutions, resolutions.counts, resolutions.sizes)):
                pct = count / total_count * 100
                pdf.table_row(
                    col_w,
                    [res, f"{count:,} ({pct:.0f}%)", _format_bytes(size)],
                    fill=(i % 2 == 0),
                )
        else:
            pdf.set_font("Helvetica", "I", 10)
            pdf.set_text_color(150, 150, 150)
            pdf.cell(0, 8, "No resolution data available.", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(2)

        # ── 5. Top Opportunities ─────────────────────────────────────
        pdf.section_title("Top Savings Opportunities")
        if opportunities:
            col_w = [65.0, 30.0, 30.0, 30.0]
            pdf.table_header(col_w, ["Title", "Codec", "Size", "Est. Savings"])
            for i, opp in enumerate(opportunities):
                title = opp.title[:30] + "..." if len(opp.title) > 30 else opp.title
                codec_str = f"{(opp.current_codec or '?').upper()} > {opp.recommended_codec.upper()}"
                pdf.table_row(
                    col_w,
                    [title, codec_str, _format_bytes(opp.file_size), _format_bytes(opp.estimated_savings)],
                    fill=(i % 2 == 0),
                )
        else:
            pdf.set_font("Helvetica", "I", 10)
            pdf.set_text_color(150, 150, 150)
            pdf.cell(0, 8, "No savings opportunities found. Your library looks great!", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(2)

        # ── 6. Server Performance ────────────────────────────────────
        pdf.section_title("Server Performance")
        if server_perf:
            col_w = [42.0, 20.0, 25.0, 28.0, 25.0, 25.0]
            pdf.table_header(col_w, ["Server", "Jobs", "Avg FPS", "Compression", "Hours", "Fail %"])
            for i, sp in enumerate(server_perf):
                name = sp.server_name[:20] + "..." if len(sp.server_name) > 20 else sp.server_name
                fps = f"{sp.avg_fps:.1f}" if sp.avg_fps is not None else "--"
                comp = f"{sp.avg_compression * 100:.1f}%" if sp.avg_compression is not None else "--"
                pdf.table_row(
                    col_w,
                    [
                        name,
                        str(sp.total_jobs),
                        fps,
                        comp,
                        f"{sp.total_time_hours:.1f}",
                        f"{sp.failure_rate * 100:.1f}%",
                    ],
                    fill=(i % 2 == 0),
                )
        else:
            pdf.set_font("Helvetica", "I", 10)
            pdf.set_text_color(150, 150, 150)
            pdf.cell(0, 8, "No server performance data available yet.", new_x="LMARGIN", new_y="NEXT")

        # ── Finalize ─────────────────────────────────────────────────
        buf = io.BytesIO()
        pdf.output(buf)
        return buf.getvalue()
