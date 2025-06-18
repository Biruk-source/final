import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'telebirr_api_service.dart'; // Adjust path if needed
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../models/job.dart'; // Adjust path if needed
import '../../services/firebase_service.dart'; // Adjust path if needed
import 'config.dart'; // <<--- IMPORT ADDED ---

class PaymentScreen extends StatefulWidget {
  final Job job;

  const PaymentScreen({super.key, required this.job});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final _formKey = GlobalKey<FormState>();
  final _phoneNumberController = TextEditingController();
  final _transactionPinController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late final TelebirrApiService _apiService;

  bool _isLoading = false;
  String _selectedPaymentMethod = 'Telebirr';
  File? _selectedImage;
  String? _statusMessage;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _apiService = TelebirrApiService(trustBadCertificate: true);
  }

  @override
  void dispose() {
    _phoneNumberController.dispose();
    _transactionPinController.dispose();
    super.dispose();
  }

  Future<bool> _requestPermission(Permission permission) async {
    if (Platform.isAndroid || Platform.isIOS) {
      var status = await permission.status;
      if (!status.isGranted) {
        final result = await permission.request();
        if (result.isPermanentlyDenied) {
          if (mounted) {
            _showErrorSnackBar(
              'Permission needed. Please enable ${permission.toString().split('.').last} in settings.',
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: openAppSettings,
              ),
            );
          }
          return false;
        } else if (!result.isGranted) {
          if (mounted) _showErrorSnackBar('Permission denied.');
          return false;
        }
      }
      return true;
    }
    return true;
  }

  Future<void> _capturePhoto() async {
    bool cameraPermission = await _requestPermission(Permission.camera);
    if (!cameraPermission || !mounted) {
      print("Camera permission denied or widget not mounted.");
      if (mounted) _showErrorSnackBar("Camera permission required.");
      return;
    }
    try {
      final XFile? pickedFile = await _picker.pickImage(
          source: ImageSource.camera, maxWidth: 1024, imageQuality: 80);
      if (pickedFile != null && mounted) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
        _showSuccessSnackBar('Photo captured.');
      }
    } catch (e) {
      print("Error capturing photo: $e");
      if (mounted) {
        _showErrorSnackBar('Failed to capture photo: ${e.toString()}');
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1024, imageQuality: 80);
      if (pickedFile != null && mounted) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) _showErrorSnackBar('Failed to pick image: ${e.toString()}');
    }
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Please fix the errors in the form.');
      return;
    }
    FocusScope.of(context).unfocus();

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none && mounted) {
      _showErrorSnackBar('No internet connection.');
      return;
    }

    if (mounted) setState(() => _isLoading = true);
    _statusMessage = null;

    try {
      String transactionIdForRecord =
          'UNKNOWN_${DateTime.now().millisecondsSinceEpoch}'; // Default

      if (_selectedPaymentMethod == 'Telebirr') {
        // This function now might set _statusMessage on error
        await _processTelebirrPayment();
        // If _processTelebirrPayment succeeded, statusMessage should be null
        if (_statusMessage == null) {
          // Use the generated merchOrderId for logging if needed, though it's internal
          // Maybe Telebirr returns a platform transaction ID? Check payResult/statusResult
          transactionIdForRecord =
              "Telebirr_${DateTime.now().millisecondsSinceEpoch}"; // Placeholder
        }
      } else {
        await _processCBEBirrPaymentWrapper();
        // If _processCBEBirrPaymentWrapper succeeded, statusMessage should be null
        if (_statusMessage == null) {
          // Get actual transaction ID from CBE result if available
          transactionIdForRecord =
              "CBE_${DateTime.now().millisecondsSinceEpoch}"; // Placeholder
        }
      }

      // Only record success if no status message (meaning no error was caught and set)
      if (mounted && _statusMessage == null) {
        await _firebaseService.createPaymentRecord(
          jobId: widget.job.id,
          amount: widget.job.budget * 1.1,
          paymentMethod: _selectedPaymentMethod,
          status: 'success',
          transactionId: transactionIdForRecord, // Use the determined ID
        );
        _showSuccessSnackBar('Payment successful via $_selectedPaymentMethod!');
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context, true);
      }
      // If _statusMessage is NOT null, the error is already displayed by the respective function
    } catch (e) {
      // This catch block might now only catch errors from _executeWithRetry or Firebase
      print('Outer Payment Processing Error: $e');
      if (mounted && _statusMessage == null) {
        // If no specific message was set by inner functions
        setState(() {
          _statusMessage =
              'Payment failed: ${e.toString().replaceFirst("Exception: ", "")}';
        });
        _showErrorSnackBar(
            'Payment failed: ${e.toString().replaceFirst("Exception: ", "")}');
      } else if (mounted && _statusMessage != null) {
        // Error already shown, just log if needed
        print("Error previously handled and displayed: $_statusMessage");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processTelebirrPayment() async {
    // **CRITICAL:** Ensure the _signRequest function in TelebirrApiService
    // builds the stringToSign EXACTLY according to Telebirr PREORDER docs.
    String? currentMerchOrderId; // Store the generated ID
    _statusMessage = null; // Reset status at the start of the attempt

    await _executeWithRetry(() async {
      try {
        // --- *** Ensure Token is Available *** ---
        print("Ensuring Telebirr App Token is available...");
        // Explicitly get the token first. The service stores it internally.
        // The generateAppToken function now throws an error if it fails.
        await _apiService.generateAppToken();
        print("App token confirmed available (or generated).");
        // --- *** End Token Check *** ---

        // 2. Create Order (Now we know _token should be set in _apiService)
        currentMerchOrderId =
            'TB_${DateTime.now().millisecondsSinceEpoch}'; // Generate unique ID
        final String payerNumber =
            _phoneNumberController.text.trim(); // Payer's number from input
        final String pin = _transactionPinController.text.trim();

        // **VERIFY PAYEE IDENTIFIER**: Assuming the config `consumerMsisdn` represents the merchant receiving account
        // If the payment should go to the job creator, you need their Telebirr MSISDN here.
        final String payeeIdentifier = AppConfig.consumerMsisdn; // Uses Config

        print(
            "Creating Telebirr order with merchOrderId: $currentMerchOrderId");
        final String? prepayId = await _apiService.createOrder(
          totalAmount: (widget.job.budget * 1.1).toStringAsFixed(2),
          merchOrderId: currentMerchOrderId!,
          title: widget.job.title.length > 30
              ? widget.job.title.substring(0, 30)
              : widget.job.title, // Max length?
          notifyUrl:
              AppConfig.notifyUrl, // Use configured notify URL // Uses Config
          payeeIdentifier: payeeIdentifier,
          // Verify businessType, payeeIdentifierType, payeeType with Telebirr docs/requirements
          businessType: 'BuyGoods', // P2PTransfer might require different setup
          payeeIdentifierType: '01', // MSISDN
          payeeType: '1000', // User
        );

        // createOrder throws an exception if prepayId is null/empty now
        print("Obtained Prepay ID: $prepayId");

        // 3. Pay Order
        // !! WARNING: _encryptPin is currently a placeholder !!
        // !! This step WILL FAIL until PIN encryption is implemented !!
        // !! with Telebirr's PUBLIC KEY !!
        print("Attempting Telebirr payOrder for prepayId: $prepayId");
        final payResult = await _apiService.payOrder(
            prepayId:
                prepayId!, // Use non-null assertion as createOrder throws if null
            payerIdentifier: payerNumber, // Payer number from input
            consumerPin:
                pin // Raw PIN passed to service (which currently uses placeholder encryption)
            );

        print("Telebirr payOrder raw result: ${jsonEncode(payResult)}");
        // payOrder throws an exception if it fails based on response code

        // 4. (Optional but Recommended) Query Order Status
        await Future.delayed(
            const Duration(seconds: 3)); // Give time for processing
        print(
            "Querying Telebirr order status for merchOrderId: $currentMerchOrderId");
        final statusResult = await _apiService.queryOrder(
            merchOrderId: currentMerchOrderId!); // Uses added method
        print("Telebirr queryOrder raw result: ${jsonEncode(statusResult)}");

        // queryOrder throws an exception if it fails based on response code
        final tradeStatus = statusResult['biz_content']?['trade_status'];
        // Add more success statuses if needed based on Telebirr docs
        if (tradeStatus != 'SUCCESS' && tradeStatus != 'Finished') {
          throw Exception(
              "Telebirr payment final status was not successful: ${tradeStatus ?? 'Unknown'}");
        }

        // If all steps passed without exception
        _statusMessage = null; // Clear any intermediate error message
      } on TimeoutException catch (e) {
        print("Telebirr Timeout: $e");
        _statusMessage =
            "Request timed out. Please check connection or try again.";
        rethrow; // Rethrow to be caught by outer handler
      } on FormatException catch (e) {
        // Catch key parsing errors from _signRequest
        print("Telebirr Key/Format Error: $e");
        _statusMessage = "Configuration error: Invalid key format.";
        rethrow;
      } catch (e) {
        // Catch errors thrown by API calls or status checks
        print("Telebirr API Error: $e");
        // Use the error message thrown by the service or checks
        _statusMessage = e.toString().replaceFirst("Exception: ", "");
        rethrow; // Rethrow to be caught by outer handler
      }
    });

    // The success handling (Firebase logging, pop) should now happen in the
    // _processPayment function AFTER this function is awaited, checking if _statusMessage is null.
    // No need to set a success message here, the absence of an error message implies success for the outer function.
  }

  Future<void> _processCBEBirrPaymentWrapper() async {
    _statusMessage = null; // Reset status
    await Future.delayed(const Duration(seconds: 3));
    if (_phoneNumberController.text.endsWith('0')) {
      _statusMessage = "Simulated CBE Birr failure."; // Set status message
      throw Exception(_statusMessage); // Throw to be caught
    }
    print("Simulating CBE Birr success.");
    // No status message set on success
  }

  Future<void> _executeWithRetry(Future<void> Function() action) async {
    _retryCount = 0;
    while (true) {
      try {
        await action();
        return;
      } catch (e) {
        _retryCount++;
        print('Attempt $_retryCount failed: $e');
        if (_retryCount >= _maxRetries) {
          print('Max retries reached. Rethrowing error.');
          rethrow;
        }
        final delay = Duration(seconds: 2 * _retryCount);
        print('Retrying in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
      }
    }
  }

  void _showErrorSnackBar(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        action: action,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Secure Payment'),
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            elevation: 2,
            centerTitle: true,
          ),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    // Order Summary
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Order Summary',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(color: colorScheme.primary)),
                          const SizedBox(height: 12),
                          _buildOrderItem('Job Title', widget.job.title),
                          const Divider(height: 20, thickness: 0.5),
                          _buildOrderItem('Service Fee (10%)',
                              'ETB ${(widget.job.budget * 0.1).toStringAsFixed(2)}'),
                          const Divider(height: 20, thickness: 0.5),
                          _buildOrderItem('Total Amount',
                              'ETB ${(widget.job.budget * 1.1).toStringAsFixed(2)}',
                              isTotal: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Select Payment Method',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _buildPaymentMethodTile('Telebirr', Icons.phone_android,
                      'Pay using Telebirr mobile money', colorScheme),
                  const SizedBox(height: 8),
                  _buildPaymentMethodTile(
                      'CBE Birr',
                      Icons.account_balance_wallet,
                      'Pay using CBE Birr wallet',
                      colorScheme),
                  const SizedBox(height: 24),
                  Form(
                    // Payment Details
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Enter Payment Details',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),
                        TextFormField(
                          // Phone Number
                          controller: _phoneNumberController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                              labelText: 'Your Phone Number (Payer)',
                              hintText: 'e.g., 0912345678',
                              prefixIcon:
                                  Icon(Icons.phone, color: colorScheme.primary),
                              border: const OutlineInputBorder()),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your phone number';
                            }
                            if (!RegExp(r'^09[0-9]{8}$').hasMatch(value)) {
                              return 'Enter a valid Ethiopian mobile number (09...)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          // PIN
                          controller: _transactionPinController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          maxLength: 6,
                          decoration: InputDecoration(
                              labelText: 'Transaction PIN',
                              hintText: 'Enter your payment PIN',
                              prefixIcon: Icon(Icons.lock_outline,
                                  color: colorScheme.primary),
                              border: const OutlineInputBorder(),
                              counterText: ""),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your PIN';
                            }
                            if (value.length < 4) {
                              return 'PIN must be at least 4 digits';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        if (_selectedPaymentMethod == 'CBE Birr') ...[
                          // CBE Proof Section
                          Text('Optional Proof (for CBE Birr)',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                OutlinedButton.icon(
                                    onPressed: _capturePhoto,
                                    icon: const Icon(Icons.camera_alt_outlined),
                                    label: const Text('Take Photo')),
                                OutlinedButton.icon(
                                    onPressed: _pickImage,
                                    icon: const Icon(Icons.image_outlined),
                                    label: const Text('Pick Image')),
                              ]),
                          const SizedBox(height: 10),
                          if (_selectedImage != null)
                            Center(
                                child: Image.file(_selectedImage!,
                                    height: 100,
                                    width: 100,
                                    fit: BoxFit.cover)),
                        ],
                        if (_statusMessage != null) // Display Error Inline
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10.0),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              color:
                                  colorScheme.errorContainer.withOpacity(0.1),
                              child: Text(_statusMessage!,
                                  style: TextStyle(color: colorScheme.error),
                                  textAlign: TextAlign.center),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    // Pay Button
                    onPressed: _isLoading ? null : _processPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 3, color: Colors.white))
                        : Text(
                            'Pay ETB ${(widget.job.budget * 1.1).toStringAsFixed(2)}'),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    // Security notice
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.security,
                          size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text('Secured Payment via $_selectedPaymentMethod',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey.shade600)),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading) // Loading Overlay
          Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                  child:
                      CircularProgressIndicator(color: colorScheme.primary))),
      ],
    );
  }

  Widget _buildOrderItem(String label, String value, {bool isTotal = false}) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
        color: isTotal ? Theme.of(context).colorScheme.primary : null);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: style),
          Text(value, style: style),
        ]));
  }

  Widget _buildPaymentMethodTile(
      String title, IconData icon, String subtitle, ColorScheme colorScheme) {
    bool isSelected = _selectedPaymentMethod == title;
    return Card(
      elevation: isSelected ? 2 : 1,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
              color: isSelected ? colorScheme.primary : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1)),
      child: InkWell(
        onTap: () {
          if (!_isLoading) {
            setState(() {
              _selectedPaymentMethod = title;
              _selectedImage = null;
              _statusMessage = null;
            });
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(children: [
              Icon(icon,
                  size: 28,
                  color:
                      isSelected ? colorScheme.primary : Colors.grey.shade600),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color:
                                    isSelected ? colorScheme.primary : null)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey.shade600)),
                    ]
                  ])),
              if (isSelected)
                Icon(Icons.check_circle, color: colorScheme.primary),
            ])),
      ),
    );
  }
}
