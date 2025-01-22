import 'package:juice/juice.dart';
import '../form.dart';

class FormWithAnimation extends StatefulWidget {
  const FormWithAnimation({super.key});

  @override
  State<StatefulWidget> createState() => FormWithAnimationState();
}

class FormWithAnimationState
    extends JuiceWidgetState<FormBloc, FormWithAnimation>
    with SingleTickerProviderStateMixin {
  FormWithAnimationState({super.groups = const {"form"}});

  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _messageController;

  final _formKey = GlobalKey<FormState>();

  @override
  void onInit() {
    super.onInit();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _slideAnimation = Tween<double>(begin: 50, end: 0).animate(CurvedAnimation(
        parent: _animationController, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));

    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: AnimatedPadding(
        padding: EdgeInsets.all(bloc.state.isSubmitting ? 8.0 : 16.0),
        duration: const Duration(milliseconds: 300),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildFormFields(),
                const SizedBox(height: 24),
                _buildSubmitButton(),
                if (bloc.state.submissionMessage.isNotEmpty)
                  _buildFeedbackMessage(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'Contact Us',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Send us a message and we\'ll get back to you soon.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        _buildTextFormField(
          controller: _nameController,
          label: 'Name',
          validator: (value) {
            if (value?.isEmpty ?? true) {
              return 'Please enter your name';
            }
            return null;
          },
          prefixIcon: const Icon(Icons.person_outline),
        ),
        const SizedBox(height: 16),
        _buildTextFormField(
          controller: _emailController,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value?.isEmpty ?? true) {
              return 'Please enter your email';
            }
            if (!value!.contains('@')) {
              return 'Please enter a valid email';
            }
            return null;
          },
          prefixIcon: const Icon(Icons.email_outlined),
        ),
        const SizedBox(height: 16),
        _buildTextFormField(
          controller: _messageController,
          label: 'Message',
          maxLines: 4,
          validator: (value) {
            if (value?.isEmpty ?? true) {
              return 'Please enter your message';
            }
            return null;
          },
          prefixIcon: const Icon(Icons.message_outlined),
        ),
      ],
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    Widget? prefixIcon,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: prefixIcon,
        filled: true,
        fillColor: Colors.grey[50],
        enabled: !bloc.state.isSubmitting,
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      // Add a fixed width container
      width: double.infinity,
      child: Center(
        // Center the animated content
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: bloc.state.isSubmitting
              ? 56
              : 200, // Use fixed widths instead of double.infinity
          height: 56,
          child: ElevatedButton(
            onPressed: bloc.state.isSubmitting ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(bloc.state.isSubmitting ? 28 : 12),
              ),
              padding: EdgeInsets.zero, // Ensure padding doesn't affect size
            ),
            child: bloc.state.isSubmitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text(
                    'Submit',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackMessage() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      bloc.state.submissionMessage,
                      style: TextStyle(color: Colors.green[700]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      final formData = {
        'name': _nameController.text,
        'email': _emailController.text,
        'message': _messageController.text,
      };
      bloc.send(SubmitFormEvent(formData));
      _animationController.forward(from: 0.0);
    }
  }
}
