import OrderDetail from "@/components/OrderDetail";

export default async function CustomerOrderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <OrderDetail sub="CUSTOMER_APP" orderId={id} />;
}
