import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// upload de imagens pro imgbb -- mesmo servico ja usado pras fotos dos
// anuncios, centralizado aqui pra nao duplicar a chamada http
class ImgbbService {
  ImgbbService._();
  static final ImgbbService instance = ImgbbService._();

  static const String _apiKey = 'a68f19850179cfd6cf7c02e8ef771012';
  static final Uri _apiUrl = Uri.parse('https://api.imgbb.com/1/upload?key=$_apiKey');

  Future<String> enviarImagem(XFile imagem) async {
    final request = http.MultipartRequest('POST', _apiUrl);
    request.files.add(await http.MultipartFile.fromPath('image', imagem.path));

    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Erro na API ImgBB: HTTP ${response.statusCode}');
    }

    final responseData = await response.stream.bytesToString();
    final jsonMap = json.decode(responseData);
    return jsonMap['data']['url'];
  }

  Future<List<String>> enviarImagens(List<XFile> imagens) async {
    final urls = <String>[];
    for (var i = 0; i < imagens.length; i++) {
      try {
        urls.add(await enviarImagem(imagens[i]));
      } catch (e) {
        throw Exception('Falha ao processar a foto ${i + 1}. Detalhes: $e');
      }
    }
    return urls;
  }
}
