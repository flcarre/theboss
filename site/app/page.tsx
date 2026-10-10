import Header from "@/components/Header";
import Hero from "@/components/Hero";
import Ticker from "@/components/Ticker";
import Tour from "@/components/Tour";
import Moods from "@/components/Moods";
import MenuBar from "@/components/MenuBar";
import Staff from "@/components/Staff";
import Rules from "@/components/Rules";
import Privacy from "@/components/Privacy";
import Install from "@/components/Install";
import Footer from "@/components/Footer";
import Reveal from "@/components/Reveal";

export default function Home() {
  return (
    <>
      <Header />
      <main id="top">
        <Hero />
        <Ticker />
        <Tour />
        <Moods />
        <MenuBar />
        <Staff />
        <Rules />
        <Privacy />
        <Install />
      </main>
      <Footer />
      <Reveal />
    </>
  );
}
