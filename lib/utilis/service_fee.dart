class ServiceFee {
  static double domestic(String sizeId) {
    switch (sizeId.toLowerCase()) {
      case 'xs': return 0.40;
      case 'sm': return 0.60;
      case 'md': return 0.80;
      case 'lg': return 1.10;
      default:   return 0.60;
    }
  }

  static double international(String sizeId) {
    switch (sizeId.toLowerCase()) {
      case 'xs': return 1.20;
      case 'sm': return 1.50;
      case 'md': return 2.00;
      case 'lg': return 2.50;
      default:   return 1.50;
    }
  }

  static double get(String sizeId, {bool isInternational = false}) =>
      isInternational ? international(sizeId) : domestic(sizeId);
}