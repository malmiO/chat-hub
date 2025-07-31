import 'dart:async';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:flutter/material.dart';
import '../controller/auth_controller.dart';
import './register_screen.dart';
import '../../../home_screen.dart';
import '../../../common/widgets/colors.dart';

class OTPScreen extends StatefulWidget {
  final String email;
  OTPScreen({required this.email});

  @override
  _OTPScreenState createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final TextEditingController otpController = TextEditingController();
  final AuthController authController = AuthController();
  bool isLoading = false;
  int resendCooldown = 30;
  bool canResend = true;
  Timer? timer;
  bool isOtpComplete = false;

  void verifyOTP() async {
    setState(() => isLoading = true);
    String? token = await authController.verifyOTP(
      widget.email,
      otpController.text.trim(),
    );
    setState(() => isLoading = false);

    if (token != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RegisterPage(email: widget.email),
        ),
      );
    }
  }

  void startCooldown() {
    setState(() {
      canResend = false;
      resendCooldown = 30;
    });
    timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (resendCooldown == 0) {
        timer.cancel();
        setState(() => canResend = true);
      } else {
        setState(() => resendCooldown--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        title: Text('Verify OTP', style: TextStyle(color: Colors.white)),
        iconTheme: IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 50),
            Icon(Icons.verified_user, color: tabColor, size: 60),
            SizedBox(height: 24),
            Text(
              'OTP Verification',
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'Enter the 6-digit code sent to',
              style: TextStyle(color: greyColor, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            Text(
              widget.email,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 40),
            PinCodeTextField(
              appContext: context,
              length: 6,
              controller: otpController,
              obscureText: false,
              animationType: AnimationType.fade,
              keyboardType: TextInputType.number,
              textStyle: TextStyle(color: Colors.white, fontSize: 20),
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(8),
                fieldHeight: 50,
                fieldWidth: 40,
                activeFillColor: chatBarMessage,
                selectedFillColor: chatBarMessage.withOpacity(0.8),
                inactiveFillColor: chatBarMessage.withOpacity(0.5),
                activeColor: tabColor,
                selectedColor: tabColor,
                inactiveColor: greyColor,
              ),
              animationDuration: Duration(milliseconds: 300),
              enableActiveFill: true,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              onChanged: (value) {
                setState(() {
                  isOtpComplete = value.length == 6;
                });
              },
            ),
            SizedBox(height: 40),
            GestureDetector(
              onTap: () {
                if (!isOtpComplete) {
                  // Shake or error message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please enter all 6 digits of the OTP.',
                        style: TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else if (!isLoading) {
                  verifyOTP();
                }
              },
              child: AnimatedContainer(
                duration: Duration(milliseconds: 300),
                padding: EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color:
                      isOtpComplete
                          ? tabColor
                          : Colors.grey, // Color based on completeness
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child:
                      isLoading
                          ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                          : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: Text(
                              'Verify OTP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                ),
              ),
            ),

            SizedBox(height: 20),
            Divider(color: dividerColor),
            SizedBox(height: 12),
            TextButton(
              onPressed:
                  canResend
                      ? () async {
                        setState(() => isLoading = true);
                        bool success = await authController.resendOTP(
                          widget.email,
                        );
                        setState(() => isLoading = false);
                        if (success) startCooldown();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success ? 'OTP resent!' : 'Failed to resend.',
                              style: TextStyle(color: Colors.white),
                            ),
                            backgroundColor:
                                success ? Colors.green : Colors.red,
                          ),
                        );
                      }
                      : null,
              child: Text(
                canResend
                    ? "Didn't receive the code? Resend"
                    : "Resend available in $resendCooldown s",
                style: TextStyle(
                  color: canResend ? tabColor : greyColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
