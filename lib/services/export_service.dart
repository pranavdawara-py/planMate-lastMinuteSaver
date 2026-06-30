import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/task.dart';

class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  Future<void> exportDaySchedule(DateTime date, List<Task> tasks) async {
    final pdf = pw.Document();

    final dateStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "planMate Agenda Plan",
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  "Scheduled Day: $dateStr",
                  style: const pw.TextStyle(
                      fontSize: 14, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 20),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 12),
                tasks.isEmpty
                    ? pw.Text("No tasks scheduled for this day.",
                        style: const pw.TextStyle(fontSize: 12))
                    : pw.Table(
                        border: pw.TableBorder.all(
                            color: PdfColors.grey400, width: 0.5),
                        children: [
                          pw.TableRow(
                            decoration:
                                const pw.BoxDecoration(color: PdfColors.grey200),
                            children: [
                              _buildCell("Title", isHeader: true),
                              _buildCell("Category", isHeader: true),
                              _buildCell("Type", isHeader: true),
                              _buildCell("Status", isHeader: true),
                            ],
                          ),
                          ...tasks.map((task) {
                            return pw.TableRow(
                              children: [
                                _buildCell(task.title),
                                _buildCell(task.category ?? "General"),
                                _buildCell(task.type.toUpperCase()),
                                _buildCell(task.status.toUpperCase()),
                              ],
                            );
                          }),
                        ],
                      ),
              ],
            ),
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'planmate_agenda_$dateStr.pdf',
    );
  }

  pw.Widget _buildCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
