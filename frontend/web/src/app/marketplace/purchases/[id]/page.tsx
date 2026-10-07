import OrderDetail from "@/components/OrderDetail";

export default async function PurchasePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <OrderDetail sub="MARKETPLACE_APP" orderId={id} />;
}
