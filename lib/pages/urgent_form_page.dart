import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
// Ajuste os imports conforme a estrutura do seu projeto
import 'package:appcbm/api/cbm_api.dart';
import 'package:appcbm/api/cbm_models.dart';
import 'qr_scanner_page.dart';

class UrgentFormPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> me;

  const UrgentFormPage({super.key, required this.token, required this.me});

  @override
  State<UrgentFormPage> createState() => _UrgentFormPageState();
}

class _UrgentFormPageState extends State<UrgentFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _salaController = TextEditingController();
  final _equipamentoController = TextEditingController();
  final _numSerieController = TextEditingController();
  final _obsController = TextEditingController();

  bool _isLoading = true; // Começa carregando enquanto lê o QR
  XFile? _imageFile;
  final _api = CbmApi();

  Equipment? _equipment;
  String? _assetId;

  @override
  void initState() {
    super.initState();
    // Abre o scanner assim que a tela é montada
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lerQrCode();
    });
  }

  @override
  void dispose() {
    _salaController.dispose();
    _equipamentoController.dispose();
    _numSerieController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  // --- LÓGICA MANTIDA (Leitura, API, Envio Sequencial) ---

  Future<void> _lerQrCode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );

    if (!mounted) return;

    if (code == null || code.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }

    _assetId = code.trim();
    await _carregarDados(_assetId!);
  }

  Future<void> _carregarDados(String code) async {
    setState(() => _isLoading = true);

    try {
      final equip = await _api.getEquipmentByCode(
        code: code,
        token: widget.token,
      );

      if (equip != null) {
        _equipment = equip;
        _preencherComEquip(equip);
      } else {
        _equipment = null;
        _equipamentoController.text = 'Equipamento não cadastrado';
        _numSerieController.text = code;
        _salaController.text = 'Local desconhecido';

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Atenção: Equipamento não encontrado no sistema.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Erro ao carregar equipamento: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _preencherComEquip(Equipment e) {
    _equipamentoController.text = e.name;
    _numSerieController.text = e.code ?? e.id.toString();
    _salaController.text = e.environment?.name ?? 'Sem local definido';
  }

  Future<void> _tirarFoto() async {
    final picker = ImagePicker();
    final foto = await picker.pickImage(source: ImageSource.camera);
    if (foto != null) setState(() => _imageFile = foto);
  }

  Future<void> _enviarChamado() async {
    if (!_formKey.currentState!.validate()) return;

    // Validação de segurança da lógica original
    if (_equipment?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Erro: Não é possível criar chamado sem um equipamento válido.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final meId = widget.me['id'] as int;
    final equipId = _equipment!.id;

    try {
      // 1. Criar a Tarefa
      final taskPayload = {
        'name': 'Urgente: ${_equipamentoController.text}',
        'description': _obsController.text.trim().isEmpty
            ? 'Chamado de urgência aberto via QR Code.'
            : _obsController.text.trim(),
        'suggested_date': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'urgency_level': 'HIGH',
        'equipments_FK': [equipId],
        'responsibles_FK': [],
      };

      final newTaskId = await _api.createTaskSimple(taskPayload, widget.token);

      if (newTaskId == null)
        throw Exception("Falha ao obter ID da nova tarefa.");

      // 2. Criar o Status Inicial
      final statusPayload = {
        'task_FK': newTaskId,
        'status': 'OPEN',
        'comment': 'Chamado de Urgência criado via App Mobile',
        'user_FK': meId,
      };

      final newStatusId = await _api.createTaskStatus(
        statusPayload,
        widget.token,
      );

      if (newStatusId == null)
        throw Exception("Falha ao criar status inicial.");

      // 3. Enviar Foto (Se houver)
      if (_imageFile != null) {
        await _api.uploadTaskStatusImage(
          imageFile: File(_imageFile!.path),
          statusId: newStatusId,
          token: widget.token,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chamado URGENTE enviado!'),
          backgroundColor:
              Colors.green, // Ou redAccent se preferir manter o alerta visual
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      print("Erro ao enviar urgente: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E2E2E), // Fundo escuro original
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : SingleChildScrollView(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0), // Card cinza claro original
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Campos de informação do equipamento (Readonly)
                        _buildTextField(
                          label: 'Equipamento',
                          controller: _equipamentoController,
                          readOnly: true,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          label: 'Nº Série',
                          controller: _numSerieController,
                          readOnly: true,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          label: 'Sala',
                          controller: _salaController,
                          readOnly: true,
                        ),

                        const SizedBox(height: 12),

                        // Campo de descrição editável
                        _buildTextField(
                          label: 'Descreva o problema',
                          controller: _obsController,
                          hint: 'Explique a urgência encontrada',
                          maxLines: 3,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Por favor, descreva o problema.'
                              : null,
                        ),

                        const SizedBox(height: 16),

                        // Preview da Foto
                        if (_imageFile != null) ...[
                          const Text(
                            'Foto Anexada:',
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_imageFile!.path),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _imageFile = null),
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Botão de Foto (Estilo Outlined cinza/escuro)
                        OutlinedButton.icon(
                          onPressed: _tirarFoto,
                          icon: const Icon(
                            Icons.camera_alt,
                            color: Color(0xFF333333),
                          ),
                          label: Text(
                            _imageFile == null ? 'ANEXAR FOTO' : 'TROCAR FOTO',
                            style: const TextStyle(color: Color(0xFF333333)),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF333333)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Botão de Enviar (Estilo Vermelho/Elevated)
                        ElevatedButton(
                          onPressed: _enviarChamado,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'FINALIZAR CHAMADO',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  // Helper de Estilo (Do código antigo)
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            // Mantém branco se editável, cinza claro se readonly
            fillColor: readOnly ? const Color(0xFFF0F0F0) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.grey),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}
